# Example: OIDC Federation for CI/CD

## Overview

This example shows how to configure OIDC federation so CI/CD pipelines authenticate to the cloud without stored credentials. The CI/CD platform provides a signed JWT; the cloud provider validates it and issues short-lived credentials.

## Terraform: OIDC Provider and Roles (Per Account)

### Root Account: Create the OIDC Provider

```hcl
# terraform-org/prod/oidc.tf
# Create the OIDC provider once in each account that needs CI/CD access

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.tags
}
```

### Per-Account Deployment Role

```hcl
# terraform-org/prod/iam.tf
# Role for infrastructure deployment -- restricted to specific repos

resource "aws_iam_role" "github_actions_deploy" {
  name = "GithubActionsDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # CRITICAL: restrict to specific repositories
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:myorg/infrastructure:*",
              "repo:myorg/terraform-org:*"
            ]
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# Attach policy -- scope to what this role actually needs
resource "aws_iam_role_policy_attachment" "deploy_admin" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

### Per-Account Application Deploy Role (More Restricted)

```hcl
# terraform-org/prod/iam_app.tf
# Role for application deployment -- restricted to app repos and scoped permissions

resource "aws_iam_role" "github_actions_app" {
  name = "GithubActionsAppDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:myorg/api-service:*",
              "repo:myorg/web-app:*",
              "repo:myorg/worker-service:*"
            ]
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.tags
}

# Scoped policy: only ECR push + ECS deploy + S3 artifacts
resource "aws_iam_role_policy" "app_deploy" {
  name = "AppDeployPolicy"
  role = aws_iam_role.github_actions_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSUpdate"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::*:role/*-task-role"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}
```

## GitHub Actions Workflow: Infrastructure Deploy

```yaml
# .github/workflows/infra-deploy.yml
name: Deploy Infrastructure
on:
  push:
    tags: ["v*"]

permissions:
  id-token: write    # Required for requesting OIDC JWT
  contents: read     # Required for actions/checkout

env:
  AWS_REGION: eu-west-1
  TF_VERSION: "1.8.0"

jobs:
  plan:
    name: Terraform Plan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GithubActionsDeployRole
          aws-region: ${{ env.AWS_REGION }}
          # No access-key-id, no secret-access-key -- pure OIDC

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init
        working-directory: 40_compute/prod

      - name: Terraform Plan
        run: terraform plan -out=tfplan
        working-directory: 40_compute/prod

      - uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: 40_compute/prod/tfplan

  apply:
    name: Terraform Apply
    needs: plan
    runs-on: ubuntu-latest
    environment: production    # Requires manual approval
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GithubActionsDeployRole
          aws-region: ${{ env.AWS_REGION }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: 40_compute/prod

      - name: Terraform Init
        run: terraform init
        working-directory: 40_compute/prod

      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan
        working-directory: 40_compute/prod
```

## GitHub Actions Workflow: Application Deploy

```yaml
# .github/workflows/app-deploy.yml
name: Deploy Application
on:
  push:
    tags: ["v*"]

permissions:
  id-token: write
  contents: read

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - uses: actions/checkout@v4

      # Authenticate via OIDC with scoped role
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/GithubActionsAppDeployRole
          aws-region: eu-west-1

      # Login to container registry (no stored credentials)
      - uses: aws-actions/amazon-ecr-login@v2

      # Build and push with git SHA tag
      - name: Build and push image
        run: |
          docker build -t $ECR_REPO:${{ github.sha }} .
          docker push $ECR_REPO:${{ github.sha }}

      # Update ECS service with new image
      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster myorg-prod-cluster \
            --service api-service \
            --force-new-deployment
```

## GCP Equivalent: Workload Identity Federation

```hcl
# GCP workload identity pool for GitHub Actions
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Actions"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allow specific repos to impersonate a service account
resource "google_service_account_iam_binding" "github_deploy" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/myorg/infrastructure",
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/myorg/api-service",
  ]
}
```

## Azure Equivalent: Federated Credentials

```hcl
# Microsoft Entra ID application with federated credential for GitHub Actions
resource "azuread_application" "github_deploy" {
  display_name = "github-actions-deploy"
}

resource "azuread_application_federated_identity_credential" "github" {
  application_id = azuread_application.github_deploy.id
  display_name   = "github-actions-infra"
  description    = "GitHub Actions OIDC for infrastructure repo"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:myorg/infrastructure:ref:refs/heads/main"
}
```
