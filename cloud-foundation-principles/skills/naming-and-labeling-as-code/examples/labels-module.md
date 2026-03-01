# Labels Module -- Complete Terraform Implementation

A reusable Terraform module that produces a name prefix and tags map for every resource. This is the first module you build, before any infrastructure.

## Module Structure

```
tf-module-labels/
├── main.tf
├── variables.tf
├── outputs.tf
└── versions.tf
```

## variables.tf

```hcl
variable "team" {
  type        = string
  description = "Team abbreviation (2-4 lowercase characters). Examples: eng, data, plat"

  validation {
    condition     = can(regex("^[a-z]{2,4}$", var.team))
    error_message = "Team must be 2-4 lowercase letters. Got: '${var.team}'."
  }
}

variable "env" {
  type        = string
  description = "Environment identifier. Must be one of: dev, staging, prod, security, log-archive, sandbox."

  validation {
    condition     = contains(["dev", "staging", "prod", "security", "log-archive", "sandbox"], var.env)
    error_message = "Environment must be one of: dev, staging, prod, security, log-archive, sandbox. Got: '${var.env}'."
  }
}

variable "name" {
  type        = string
  description = "Service or project name (lowercase, alphanumeric with hyphens). Examples: api, warehouse, backend"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.name))
    error_message = "Name must start with a lowercase letter and contain only lowercase alphanumeric characters and hyphens. Got: '${var.name}'."
  }
}

variable "cost_center" {
  type        = string
  description = "Cost allocation category from the approved list."

  validation {
    condition = contains([
      "engineering",
      "data",
      "infrastructure",
      "security",
      "operations",
    ], var.cost_center)
    error_message = "Invalid cost_center '${var.cost_center}'. Must be one of: engineering, data, infrastructure, security, operations."
  }
}

variable "scope" {
  type        = string
  description = "Optional scope qualifier. Use 'g' for global resources. Leave empty for regional."
  default     = ""

  validation {
    condition     = var.scope == "" || can(regex("^[a-z]{1,10}$", var.scope))
    error_message = "Scope must be empty or 1-10 lowercase letters."
  }
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional tags to merge with the standard tags. Cannot override standard tags."
  default     = {}
}
```

## main.tf

```hcl
locals {
  # Build the prefix: <team>-<env>[-<scope>]-<name>-
  scope_segment = var.scope != "" ? "-${var.scope}" : ""
  prefix        = "${lower(var.team)}-${lower(var.env)}${local.scope_segment}-${lower(var.name)}-"

  # Standard tags applied to every resource
  standard_tags = {
    owner       = lower(var.team)
    environment = lower(var.env)
    project     = lower(var.name)
    cost_center = lower(var.cost_center)
    managed_by  = "terraform"
  }

  # Merge additional tags (standard tags take precedence)
  tags = merge(var.additional_tags, local.standard_tags)

  # Approved cost centers (single source of truth)
  cost_center_list = [
    "engineering",
    "data",
    "infrastructure",
    "security",
    "operations",
  ]
}
```

## outputs.tf

```hcl
output "prefix" {
  description = "Name prefix for all resources: <team>-<env>[-<scope>]-<name>-"
  value       = local.prefix
}

output "tags" {
  description = "Standard tag map to apply to all resources"
  value       = local.tags
}

output "cost_center_list" {
  description = "List of approved cost centers"
  value       = local.cost_center_list
}

output "team" {
  description = "Team abbreviation (lowercase)"
  value       = lower(var.team)
}

output "env" {
  description = "Environment identifier (lowercase)"
  value       = lower(var.env)
}

output "name" {
  description = "Service name (lowercase)"
  value       = lower(var.name)
}
```

## versions.tf

```hcl
terraform {
  required_version = ">= 1.5.0"
}
```

## Example: What Happens with Invalid Input

```
$ terraform plan

Error: Invalid value for variable

  on main.tf line 5, in module "labels":
   5:   cost_center = "web_team"

Invalid cost_center 'web_team'. Must be one of: engineering, data,
infrastructure, security, operations.
```

The engineer sees the error, picks from the list, and the plan succeeds. No invalid cost centers ever reach a cloud resource.

## Example: Resulting Prefix and Tags

Given these inputs:
```hcl
module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.0.0"
  team        = "eng"
  env         = "prod"
  name        = "api"
  cost_center = "engineering"
  scope       = "g"
}
```

The outputs are:
```
prefix = "eng-prod-g-api-"

tags = {
  owner       = "eng"
  environment = "prod"
  project     = "api"
  cost_center = "engineering"
  managed_by  = "terraform"
}
```
