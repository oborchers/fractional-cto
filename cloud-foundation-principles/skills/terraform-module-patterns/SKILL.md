---
name: terraform-module-patterns
description: "This skill should be used when the user is designing Terraform modules, wrapping community modules, implementing conditional resource creation, structuring module variables and outputs, setting up pre-commit quality gates, versioning custom modules, building reusable infrastructure components, or reviewing module code for maintainability. Covers ten production-proven module design patterns, quality gate configuration, and version pinning strategies."
version: 1.0.0
---

# Ten Module Patterns That Survive Production

A Terraform module is a contract between the team that builds infrastructure and the teams that consume it. Bad modules expose too many knobs, force consumers to understand implementation details, and break silently when upstream dependencies change. Good modules encode organizational standards, provide sensible defaults, validate inputs at the boundary, and evolve on their own release cycle without breaking consumers.

These ten patterns come from production infrastructure managing multiple environments and hundreds of resources. Every pattern exists because its absence caused an incident, a bottleneck, or a maintenance burden.

## Pattern 1: Wrap, Don't Rebuild

Never rewrite what the community has already built and battle-tested. Before building any module, research what already exists -- `terraform-aws-modules`, `terraform-google-modules`, and cloud provider-maintained modules (especially from AWS) are production-hardened and cover most use cases. Use prebuilt modules wherever possible. Only build what is absolutely necessary: your domain-specific wrapper logic on top.

```hcl
# Good: Wrap the community ECS module with domain logic
module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  # Bridge: calculate total CPU/memory from container definitions
  cpu    = sum([for c in var.containers : c.cpu])
  memory = sum([for c in var.containers : c.memory])

  tags = var.tags
}
```

```hcl
# Bad: 400 lines reimplementing ECS service from scratch
resource "aws_ecs_service" "this" { ... }
resource "aws_ecs_task_definition" "this" { ... }
resource "aws_iam_role" "execution" { ... }
resource "aws_iam_role" "task" { ... }
resource "aws_iam_role_policy_attachment" "execution" { ... }
# ...20 more resources that terraform-aws-modules already handles
```

**Why**: Community modules handle edge cases you have not encountered yet and receive security patches from hundreds of contributors.

## Pattern 2: Single Source of Truth for Naming

Create a labels module as your first Terraform module. Import it once per project. Use it for every resource name and tag. Never construct names or tags manually. The labels module's interface, naming pattern, and cost center validation are defined in the `naming-and-labeling-as-code` skill -- this pattern is about *why* it matters at the module design level.

```hcl
# Import ONCE per project (interface defined in naming-and-labeling-as-code skill)
module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "platform"
  env         = "dev"
  name        = "backend"
  cost_center = "engineering"
  scope       = "g"
}

# Use EVERYWHERE
locals {
  tags = module.labels.tags
  prefix = module.labels.prefix
}

resource "aws_s3_bucket" "data" {
  bucket = "${local.prefix}data"
  tags   = local.tags
}

resource "aws_sqs_queue" "events" {
  name = "${local.prefix}events"
  tags = local.tags
}
```

**Why**: Consistent naming across hundreds of resources is impossible to enforce manually. The labels module makes inconsistency structurally impossible.

## Pattern 3: Conditional Resource Creation

Provide two mechanisms for disabling resources: a module-level `create` toggle and per-feature threshold-based disabling.

### Module-level toggle
```hcl
variable "create" {
  type    = bool
  default = true
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = var.create ? 1 : 0
  # ...
}
```

### Per-feature toggle via threshold
```hcl
variable "cpu_utilization_threshold" {
  type        = number
  default     = 80
  description = "CPU alarm threshold in percent. Set to -1 to disable."
}

locals {
  create_cpu_alarm = var.cpu_utilization_threshold >= 0
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count     = local.create_cpu_alarm ? 1 : 0
  threshold = var.cpu_utilization_threshold
  # ...
}
```

**Why**: One variable controls both the threshold and whether the resource exists -- more elegant than a sprawl of boolean variables (`enable_cpu_alarm`, `enable_memory_alarm`, `enable_disk_alarm`).

## Pattern 4: Smart Defaults with Optional Fields

Use HCL's `optional()` type constructor to provide clean variable interfaces. Required fields are required. Optional fields have sensible defaults. Consumers only specify what differs from the default.

```hcl
variable "containers" {
  type = list(object({
    name    = string                              # Required
    image   = string                              # Required
    cpu     = number                              # Required
    memory  = number                              # Required
    port    = optional(number, 8080)              # Default: 8080
    health_check_path    = optional(string, "/health")
    health_check_matcher = optional(string, "200")
    desired_count        = optional(number, 2)
    environment          = optional(list(object({
      name  = string
      value = string
    })), [])
  }))
}
```

**Minimal consumer usage:**
```hcl
module "service" {
  source = "git::https://github.com/myorg/tf-module-container-service.git?ref=v2.0.0"

  containers = [{
    name   = "api"
    image  = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/myapp:abc1234"
    cpu    = 1024
    memory = 2048
    # port, health_check_path, health_check_matcher, desired_count all use defaults
  }]
}
```

**Why**: The fewer fields a consumer must specify, the fewer mistakes they can make. Sensible defaults encode organizational standards silently.

## Pattern 5: Lookup-Style Outputs

Export outputs as maps keyed by natural identifiers, not array indices. Consumers should never need to know internal ordering.

```hcl
# Good: Map keyed by container name and port
output "target_groups" {
  value = {
    for key, tg in aws_lb_target_group.this :
    key => {
      arn  = tg.arn
      name = tg.name
      port = tg.port
    }
  }
  # Usage: module.service.target_groups["api-8080"].arn
}
```

```hcl
# Bad: List output that depends on internal ordering
output "target_group_arns" {
  value = aws_lb_target_group.this[*].arn
  # Usage: module.service.target_group_arns[0]  -- What is index 0?
}
```

**Why**: Array indices break when internal ordering changes. Natural keys (`"api-8080"`, `"worker-9090"`) are self-documenting and stable.

## Pattern 6: Locals for Complex Transforms

Put complex transformations in `locals`, not inline in resources. This makes logic testable, readable, and reusable across multiple resources.

```hcl
locals {
  # Flatten container ports into target group definitions
  target_groups = flatten([
    for container in var.containers : [
      for port in container.ports : {
        key                = "${container.name}-${port.container_port}"
        name_prefix        = substr(replace("${container.name}${port.container_port}", "/[^a-zA-Z0-9]/", ""), 0, 6)
        container_name     = container.name
        container_port     = port.container_port
        health_check_path  = port.health_check_path
      }
    ]
  ])

  # Convert list to map for for_each usage
  target_group_map = { for tg in local.target_groups : tg.key => tg }
}

# Resource uses the pre-computed map -- clean and simple
resource "aws_lb_target_group" "this" {
  for_each = local.target_group_map

  name_prefix = each.value.name_prefix
  port        = each.value.container_port
  # ...
}
```

**Why**: Locals separate data transformation from resource declaration -- readable, reusable, debuggable.

## Pattern 7: Validate at the Boundary

Catch errors at `terraform plan` time, not at apply time or runtime. Use `validation` blocks with `contains()` checks and clear error messages.

```hcl
# Environment validation -- catch invalid values at plan time
variable "env" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["dev", "staging", "prod", "security", "log-archive", "sandbox"], var.env)
    error_message = "env must be one of: dev, staging, prod, security, log-archive."
  }
}
```

For cost center validation (closed domain lists, enforcement at plan time), see the `naming-and-labeling-as-code` skill -- it owns the canonical pattern and list.

**Why**: An invalid cost center caught during `plan` is a 10-second fix. The same error discovered in a billing report three months later is a multi-day forensic investigation.

## Pattern 8: Modular Substructure with Identical Interfaces

When a module covers multiple service types (e.g., alerts for different cloud resources), use submodules that share an identical variable interface.

```
tf-module-alerts/
+-- main.tf           <-- Entry point
+-- ec2/              <-- Standard interface + EC2-specific thresholds
+-- rds/              <-- Standard interface + RDS-specific thresholds
+-- alb/              <-- Standard interface + ALB-specific thresholds
+-- cache/            <-- Standard interface + cache-specific thresholds
```

Every submodule accepts the same base variables: `create`, `name`, `tags`, `notification_emails`, `evaluation_periods`, `period`. Service-specific thresholds are added on top.

**Why**: Consumers learn the pattern once. Switching from EC2 alerts to container alerts requires no new interface learning.

## Pattern 9: Environment Variable Injection

Modules that deploy compute resources should automatically inject infrastructure-level environment variables. Consumers should not need to remember which variables their containers need for the platform to function.

```hcl
locals {
  # Module automatically adds infrastructure env vars
  container_definitions = [
    for container in var.containers : merge(container, {
      environment = concat(
        coalesce(container.environment, []),  # User-provided vars
        [
          { name = "SERVICE_NAME",  value = container.name },
          { name = "ENVIRONMENT",   value = var.env },
          { name = "LOG_LEVEL",     value = var.env == "prod" ? "warn" : "debug" },
          { name = "OTEL_ENDPOINT", value = var.observability_endpoint },
        ]
      )
    })
  ]
}
```

```hcl
# Consumer only specifies business-level env vars
module "service" {
  source = "git::https://github.com/myorg/tf-module-container-service.git?ref=v2.0.0"

  containers = [{
    name   = "api"
    image  = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/myapp:abc1234"
    cpu    = 1024
    memory = 2048
    environment = [
      { name = "DATABASE_URL", value = "postgres://..." },
    ]
    # SERVICE_NAME, ENVIRONMENT, LOG_LEVEL, OTEL_ENDPOINT are injected automatically
  }]
}
```

**Why**: Infrastructure concerns (observability, environment identification, logging) are injected by the module. Consumers focus on business configuration. Forgetting to set `OTEL_ENDPOINT` in one of fifty services is no longer possible.

## Pattern 10: Version Pinning

Pin everything. No exceptions. No "latest." No unversioned references.

```hcl
# Custom modules: exact git ref tags
module "labels" {
  source = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
}

# Community modules: exact version
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"
}

# Providers: pessimistic constraint
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

| Type | Pinning Strategy | Example |
|------|------------------|---------|
| Custom modules | Exact git ref tag | `?ref=v1.3.0` |
| Community modules | Exact version | `version = "5.19.0"` |
| Providers | Pessimistic constraint | `version = "~> 5.0"` |
| Terraform itself | Minimum version | `required_version = ">= 1.8.0"` |

**Why**: Unpinned modules pull the latest version on every `terraform init`, introducing silent changes that cause plan diffs, apply failures, or resources being replaced in production.

## Quality Gates

Every module repository should enforce formatting, linting, and security scanning before code enters the main branch. For the complete `.pre-commit-config.yaml` configuration, see the `tag-based-production-deploys` skill.

### What Each Gate Catches

| Gate | Catches | Example |
|------|---------|---------|
| `terraform_fmt` | Inconsistent formatting | Tabs vs spaces, trailing whitespace |
| `terraform_tflint` | Deprecated syntax, invalid references, naming violations | Previous-generation instance types, undocumented variables |
| `terraform_checkov` (optional) | Security misconfigurations, compliance violations | Unencrypted S3 buckets, security groups open to 0.0.0.0/0. Can produce false positives -- evaluate whether the signal-to-noise ratio justifies the gate for your codebase. |

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Community module registry | `terraform-aws-modules/*` | `terraform-google-modules/*` | `Azure/*` on Terraform Registry |
| Module source (git) | `git::https://github.com/myorg/module.git?ref=v1.0.0` | Same | Same |
| Module source (registry) | `terraform-aws-modules/vpc/aws` | `terraform-google-modules/network/google` | `Azure/network/azurerm` |
| Variable validation | `validation { condition = ... }` | Same | Same |
| Pre-commit hooks | `pre-commit-terraform` | Same | Same |
| Linting | TFLint + AWS ruleset | TFLint + GCP ruleset | TFLint + Azure ruleset |
| Security scanning | Checkov, tfsec | Checkov, tfsec | Checkov, tfsec |

## Examples

Working implementations in `examples/`:
- **`examples/wrapper-module.md`** -- A complete module that wraps a community container service module, adds smart defaults, conditional creation, environment variable injection, and lookup-style outputs
- **`examples/quality-gate-setup.md`** -- Pre-commit configuration, TFLint rules, and Checkov setup for a Terraform module repository

## Review Checklist

When designing or reviewing Terraform modules:

- [ ] Module wraps community modules where available rather than reimplementing from scratch
- [ ] A labels module is imported once per project and used for all resource names and tags
- [ ] Conditional creation uses `count` with a `create` variable or threshold-based disabling (`-1`)
- [ ] Variable interfaces use `optional()` with sensible defaults to minimize required consumer input
- [ ] Outputs are maps keyed by natural identifiers, not lists indexed by position
- [ ] Complex transformations live in `locals`, not inline in resource blocks
- [ ] All variables with constrained values have `validation` blocks with clear error messages
- [ ] Multi-service modules use submodules with identical variable interfaces
- [ ] Infrastructure-level environment variables are injected automatically by the module
- [ ] Custom modules are pinned to exact git ref tags (`?ref=v1.3.0`)
- [ ] Community modules are pinned to exact versions (`version = "5.19.0"`)
- [ ] Provider versions use pessimistic constraints (`~> 5.0`)
- [ ] Pre-commit hooks enforce `terraform_fmt` and `terraform_tflint`; `terraform_checkov` is recommended but optional (evaluate false positive rate for your codebase)
- [ ] Module README documents the public interface (inputs, outputs, examples)
