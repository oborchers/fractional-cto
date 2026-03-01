# CI/CD Pipeline Roles: Plan, Build, Deploy

Demonstrates the role-per-pipeline-type pattern for CI/CD OIDC authentication. Each pipeline type gets its own IAM role with subject claim restrictions that limit which branches and events can assume it.

For the OIDC provider setup (trust policies, provider configuration, GCP Workload Identity Federation), see the `zero-static-credentials` skill (`examples/oidc-federation.md`).

## Three Roles, Three Scopes

```hcl
# iam-cicd-roles.tf

# --- Plan-Only Role (used during PRs) ---
# Can only read state and generate plans, never apply
resource "aws_iam_role" "github_actions_plan" {
  name = "${module.labels.prefix}github-actions-plan"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.github_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # Any branch or PR from these repos can plan
            "token.actions.githubusercontent.com:sub" = [
              "repo:myorg/infrastructure:*",
              "repo:myorg/myapp-api:*",
              "repo:myorg/billing-service:*"
            ]
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = module.labels.tags
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Additional policy for state bucket access (plan needs to read/write state lock)
resource "aws_iam_role_policy" "plan_state_access" {
  name = "terraform-state-access"
  role = aws_iam_role.github_actions_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.state_bucket_name}",
          "arn:aws:s3:::${var.state_bucket_name}/*"
        ]
      }
    ]
  })
}

# --- Deploy Role (used for terraform apply and app deployments) ---
# Restricted to tag pushes only
resource "aws_iam_role" "github_actions_deploy" {
  name = "${module.labels.prefix}github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.github_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # ONLY tag pushes can assume this role
            "token.actions.githubusercontent.com:sub" = [
              "repo:myorg/infrastructure:ref:refs/tags/*",
              "repo:myorg/myapp-api:ref:refs/tags/*",
              "repo:myorg/billing-service:ref:refs/tags/*"
            ]
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = module.labels.tags
}

# Deploy role gets broader permissions (scoped to what Terraform needs)
resource "aws_iam_role_policy_attachment" "deploy_permissions" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.terraform_deploy.arn
}

# --- Build Role (used for container image builds) ---
# Can push to ECR, nothing else
resource "aws_iam_role" "github_actions_build" {
  name = "${module.labels.prefix}github-actions-build"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.github_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # Any branch push can build (dev deploys from branches)
            "token.actions.githubusercontent.com:sub" = [
              "repo:myorg/myapp-api:ref:refs/heads/*",
              "repo:myorg/myapp-api:ref:refs/tags/*"
            ]
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = module.labels.tags
}

resource "aws_iam_role_policy" "build_ecr_push" {
  name = "ecr-push"
  role = aws_iam_role.github_actions_build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:${var.region}:${var.account_id}:repository/*"
      }
    ]
  })
}
```

## Using the Roles in Workflows

```yaml
# CI workflow (PRs): uses plan-only role
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::role/github-actions-plan
    aws-region: eu-west-1
    # No access key, no secret key -- OIDC only

# Build workflow (pushes): uses build role
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::role/github-actions-build
    aws-region: eu-west-1

# CD workflow (tags): uses deploy role
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::role/github-actions-deploy
    aws-region: eu-west-1
```

## Role Summary

| Role | Can Assume From | Permissions | Use Case |
|------|----------------|-------------|----------|
| Plan | Any branch/PR from listed repos | ReadOnly + state access | `terraform plan` in PR CI |
| Build | Any branch or tag from listed repos | ECR push only | Docker build and push |
| Deploy | Only tag pushes from listed repos | Terraform deploy permissions | `terraform apply` in production |

### Security Boundaries

- **Plan role**: Cannot modify any infrastructure. Even if compromised, the worst case is information disclosure (reading resource configurations).
- **Build role**: Can only push container images. Cannot deploy, cannot modify infrastructure, cannot read secrets.
- **Deploy role**: Full deployment permissions but only assumable from tag pushes. A compromised branch cannot trigger a production deployment.
