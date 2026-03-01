# Example: SSO Permission Sets and Group Assignments

## Overview

This example configures SSO with an external identity provider, three permission tiers, and per-account access scoping. When an employee joins, they are added to the IdP and assigned to a group. When they leave, disabling the IdP account revokes all cloud access instantly.

## SSO Configuration (terraform-org/root/sso.tf)

### Identity Store Groups

```hcl
# Groups mirror the external IdP groups
# Members are synced automatically via SCIM or managed manually

resource "aws_identitystore_group" "admin_team" {
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  display_name      = "admin_team"
  description       = "Infrastructure administrators (2-3 people max)"
}

resource "aws_identitystore_group" "dev_team" {
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  display_name      = "dev_team"
  description       = "Application developers"
}

resource "aws_identitystore_group" "audit_team" {
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  display_name      = "audit_team"
  description       = "Compliance and audit read-only access"
}
```

### Permission Set: Administrator

```hcl
# Full admin -- limited to 2-3 people
resource "aws_ssoadmin_permission_set" "admin" {
  name             = "AdministratorAccess"
  description      = "Full administrator access to all services"
  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  session_duration = "PT8H"  # 8-hour sessions

  tags = local.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
}
```

### Permission Set: Developer

```hcl
# Granular developer access -- full in dev, scoped in prod
resource "aws_ssoadmin_permission_set" "developer" {
  name             = "DeveloperAccess"
  description      = "Full dev access, read-only prod with targeted exceptions"
  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  session_duration = "PT8H"

  tags = local.tags
}

# Custom policy for developer access
resource "aws_ssoadmin_permission_set_inline_policy" "developer" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadOnlyBase"
        Effect   = "Allow"
        Action   = [
          "ec2:Describe*",
          "ecs:Describe*",
          "ecs:List*",
          "rds:Describe*",
          "s3:Get*",
          "s3:List*",
          "cloudwatch:Get*",
          "cloudwatch:List*",
          "cloudwatch:Describe*",
          "logs:Get*",
          "logs:Describe*",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
        ]
        Resource = "*"
      },
      {
        Sid      = "ECRReadOnly"
        Effect   = "Allow"
        Action   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
        ]
        Resource = "*"
      },
      {
        Sid      = "ECSExecForDebugging"
        Effect   = "Allow"
        Action   = [
          "ecs:ExecuteCommand",
          "ssm:StartSession",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      }
    ]
  })
}
```

### Permission Set: Read Only

```hcl
# View-only for audit and compliance
resource "aws_ssoadmin_permission_set" "readonly" {
  name             = "ReadOnlyAccess"
  description      = "View-only access for audit and compliance"
  instance_arn     = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  session_duration = "PT8H"

  tags = local.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly" {
  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.readonly.arn
}
```

## Account Assignments

```hcl
# Map of account assignments: who gets what access where
locals {
  account_assignments = {
    # Admin team: full access everywhere
    admin_all = {
      group          = aws_identitystore_group.admin_team.group_id
      permission_set = aws_ssoadmin_permission_set.admin.arn
      accounts       = [var.account_ids["dev"], var.account_ids["prod"], var.account_ids["security"], var.account_ids["sandbox"]]
    }

    # Dev team: full access in dev + sandbox
    dev_full = {
      group          = aws_identitystore_group.dev_team.group_id
      permission_set = aws_ssoadmin_permission_set.admin.arn
      accounts       = [var.account_ids["dev"], var.account_ids["sandbox"]]
    }

    # Dev team: scoped access in prod (read-only + debugging)
    dev_prod = {
      group          = aws_identitystore_group.dev_team.group_id
      permission_set = aws_ssoadmin_permission_set.developer.arn
      accounts       = [var.account_ids["prod"]]
    }

    # Audit team: read-only everywhere
    audit_all = {
      group          = aws_identitystore_group.audit_team.group_id
      permission_set = aws_ssoadmin_permission_set.readonly.arn
      accounts       = [var.account_ids["dev"], var.account_ids["prod"], var.account_ids["security"]]
    }
  }

  # Flatten for for_each
  flat_assignments = flatten([
    for key, assignment in local.account_assignments : [
      for account_id in assignment.accounts : {
        key            = "${key}-${account_id}"
        group_id       = assignment.group
        permission_set = assignment.permission_set
        account_id     = account_id
      }
    ]
  ])
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = { for a in local.flat_assignments : a.key => a }

  instance_arn       = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  permission_set_arn = each.value.permission_set

  principal_id   = each.value.group_id
  principal_type = "GROUP"

  target_id   = each.value.account_id
  target_type = "AWS_ACCOUNT"
}
```

## Account IDs Variable

```hcl
variable "account_ids" {
  type = map(string)
  default = {
    dev      = "111111111111"
    prod     = "222222222222"
    security = "333333333333"
    sandbox  = "444444444444"
  }
}
```

## User Management

```hcl
# Users are created in the Identity Store
# In practice, use SCIM auto-provisioning from your IdP (Google, Okta, Entra)
# Manual creation shown here for clarity

resource "aws_identitystore_user" "users" {
  for_each = var.users

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  display_name = each.value.display_name
  user_name    = each.value.email

  name {
    given_name  = each.value.first_name
    family_name = each.value.last_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

# Group membership
resource "aws_identitystore_group_membership" "dev_team" {
  for_each = { for u in var.users : u.email => u if u.team == "dev" }

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  group_id          = aws_identitystore_group.dev_team.group_id
  member_id         = aws_identitystore_user.users[each.key].user_id
}

resource "aws_identitystore_group_membership" "admin_team" {
  for_each = { for u in var.users : u.email => u if u.team == "admin" }

  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
  group_id          = aws_identitystore_group.admin_team.group_id
  member_id         = aws_identitystore_user.users[each.key].user_id
}
```

## Users Variable

```hcl
variable "users" {
  type = map(object({
    email        = string
    display_name = string
    first_name   = string
    last_name    = string
    team         = string   # "admin", "dev", or "audit"
  }))

  default = {
    "alice" = {
      email        = "alice@myorg.com"
      display_name = "Alice Chen"
      first_name   = "Alice"
      last_name    = "Chen"
      team         = "admin"
    }
    "bob" = {
      email        = "bob@myorg.com"
      display_name = "Bob Park"
      first_name   = "Bob"
      last_name    = "Park"
      team         = "dev"
    }
  }
}
```

## Access Summary

```
Admin Team (2-3 people):
  dev      -> AdministratorAccess
  prod     -> AdministratorAccess
  security -> AdministratorAccess
  sandbox  -> AdministratorAccess

Dev Team (all developers):
  dev      -> AdministratorAccess (full access for development)
  sandbox  -> AdministratorAccess (full access for experimentation)
  prod     -> DeveloperAccess (read-only + debugging exceptions)

Audit Team (compliance):
  dev      -> ReadOnlyAccess
  prod     -> ReadOnlyAccess
  security -> ReadOnlyAccess

Offboarding:
  1. Disable user in IdP (Google Workspace, Okta, Entra)
  2. All SSO sessions invalidated immediately
  3. No cloud-side cleanup needed
  4. No API keys to hunt down
  5. No SSH keys to remove from instances
```
