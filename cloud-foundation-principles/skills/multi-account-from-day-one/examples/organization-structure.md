# Organization Structure -- Terraform Module

A six-account organization with OUs, baseline policies, and account email conventions. This is the minimum viable multi-account setup.

## Organization and OUs

```hcl
# organization/main.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Organization
# -----------------------------------------------------------------------------
resource "aws_organizations_organization" "root" {
  feature_set = "ALL"

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]
}

# -----------------------------------------------------------------------------
# Organization Units
# -----------------------------------------------------------------------------
resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.root.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.root.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads_production" {
  name      = "Production"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "workloads_development" {
  name      = "Development"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.root.roots[0].id
}
```

## Account Definitions

```hcl
# organization/accounts.tf

# Email convention: cloud-<purpose>@mycompany.com (distribution lists, not personal)

resource "aws_organizations_account" "security" {
  name      = "security"
  email     = "cloud-security@mycompany.com"
  parent_id = aws_organizations_organizational_unit.security.id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    environment = "security"
    managed_by  = "terraform"
    owner       = "platform"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "log_archive" {
  name      = "log-archive"
  email     = "cloud-log-archive@mycompany.com"
  parent_id = aws_organizations_organizational_unit.security.id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    environment = "log-archive"
    managed_by  = "terraform"
    owner       = "platform"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "sandbox" {
  name      = "sandbox"
  email     = "cloud-sandbox@mycompany.com"
  parent_id = aws_organizations_organizational_unit.sandbox.id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    environment = "sandbox"
    managed_by  = "terraform"
    owner       = "platform"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "dev" {
  name      = "dev"
  email     = "cloud-dev@mycompany.com"
  parent_id = aws_organizations_organizational_unit.workloads_development.id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    environment = "dev"
    managed_by  = "terraform"
    owner       = "platform"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "prod" {
  name      = "prod"
  email     = "cloud-prod@mycompany.com"
  parent_id = aws_organizations_organizational_unit.workloads_production.id
  role_name = "OrganizationAccountAccessRole"

  tags = {
    environment = "prod"
    managed_by  = "terraform"
    owner       = "platform"
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}
```

## Service Control Policy -- Deny Root User Actions

```hcl
# organization/scp.tf

# Prevent root user from performing any action in child accounts
resource "aws_organizations_policy" "deny_root_user" {
  name        = "deny-root-user-actions"
  description = "Prevent the root user from performing actions in member accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyRootUserActions"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_root_workloads" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = aws_organizations_organizational_unit.workloads.id
}
```

## Tag Policy -- Enforce Required Tags

```hcl
# organization/tag_policy.tf

resource "aws_organizations_policy" "required_tags" {
  name        = "enforce-required-tags"
  description = "Enforce required tags on all resources"
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      environment = {
        tag_key = {
          "@@assign" = "environment"
        }
        tag_value = {
          "@@assign" = ["dev", "staging", "prod", "security", "sandbox", "log-archive"]
        }
        enforced_for = {
          "@@assign" = [
            "s3:bucket",
            "ec2:instance",
            "rds:db",
            "lambda:function"
          ]
        }
      }
      owner = {
        tag_key = {
          "@@assign" = "owner"
        }
      }
      cost_center = {
        tag_key = {
          "@@assign" = "cost_center"
        }
      }
    }
  })
}

resource "aws_organizations_policy_attachment" "required_tags_workloads" {
  policy_id = aws_organizations_policy.required_tags.id
  target_id = aws_organizations_organizational_unit.workloads.id
}
```

## Resulting Structure

```
Root (management account -- cloud-management@mycompany.com)
├── Security OU
│   ├── security (cloud-security@mycompany.com)
│   └── log-archive (cloud-log-archive@mycompany.com)
│
├── Sandbox OU
│   └── sandbox (cloud-sandbox@mycompany.com)
│
└── Workloads OU
    ├── Production
    │   └── prod (cloud-prod@mycompany.com)
    └── Development
        └── dev (cloud-dev@mycompany.com)
```

## GCP Equivalent (Organization + Folders)

```hcl
resource "google_folder" "security" {
  display_name = "Security"
  parent       = "organizations/${var.org_id}"
}

resource "google_folder" "workloads" {
  display_name = "Workloads"
  parent       = "organizations/${var.org_id}"
}

resource "google_folder" "workloads_production" {
  display_name = "Production"
  parent       = google_folder.workloads.name
}

resource "google_folder" "workloads_development" {
  display_name = "Development"
  parent       = google_folder.workloads.name
}

resource "google_project" "dev" {
  name            = "myapp-dev"
  project_id      = "myapp-dev-${random_id.project.hex}"
  folder_id       = google_folder.workloads_development.name
  billing_account = var.billing_account_id

  labels = {
    environment = "dev"
    owner       = "platform"
    managed_by  = "terraform"
  }
}

resource "google_project" "prod" {
  name            = "myapp-prod"
  project_id      = "myapp-prod-${random_id.project.hex}"
  folder_id       = google_folder.workloads_production.name
  billing_account = var.billing_account_id

  labels = {
    environment = "prod"
    owner       = "platform"
    managed_by  = "terraform"
  }
}
```
