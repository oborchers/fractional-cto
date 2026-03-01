---
name: naming-and-labeling-as-code
description: "This skill should be used when the user is designing resource naming conventions, implementing tagging or labeling strategies, building a labels module, setting up cost center attribution, creating naming standards for cloud resources, or reviewing tag compliance. Covers naming patterns, labels modules, cost center validation, tag enforcement, and naming across resource types."
version: 1.0.0
---

# Name Every Resource Before You Create Any Resource

A naming convention designed on day one takes an hour. A naming convention retrofitted after six months of resource creation is a project. After a year, it is a migration. The labels module -- a single Terraform module that produces a name prefix and a tags map -- is the first deliverable of any cloud infrastructure project. It ships before the first VPC, before the first database, before the first storage bucket. Every resource that follows consumes its outputs. Invalid names and missing cost centers are rejected at `terraform plan`, not discovered in a cost review three months later.

## The Labels Module Pattern

The labels module is a single module that every Terraform project imports once. It takes a small set of inputs and produces two outputs that every resource uses: a name prefix and a tags map.

### Inputs

| Variable | Required | Description | Examples |
|----------|----------|-------------|----------|
| `team` | Yes | Team abbreviation (2-4 chars) | `eng`, `data`, `plat` |
| `env` | Yes | Environment identifier | `dev`, `staging`, `prod`, `security`, `log-archive`, `sandbox` |
| `name` | Yes | Service or project name | `backend`, `warehouse`, `api` |
| `cost_center` | Yes | Validated cost allocation category | `engineering`, `data`, `infrastructure` |
| `scope` | No | Scope qualifier (e.g., global) | `g`, `regional` |

### Outputs

| Output | Type | Description | Example |
|--------|------|-------------|---------|
| `prefix` | `string` | Name prefix for all resources | `eng-prod-g-backend-` |
| `tags` | `map(string)` | Standard tag map applied to all resources | `{ owner = "eng", environment = "prod", ... }` |
| `cost_center_list` | `list(string)` | Valid cost centers for reference | `["engineering", "data", ...]` |

### Usage

```hcl
module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.0.0"
  team        = "eng"
  env         = "prod"
  name        = "api"
  cost_center = "engineering"
  scope       = "g"
}

locals {
  tags = module.labels.tags
  prefix = module.labels.prefix   # "eng-prod-g-api-"
}

# Every resource uses the prefix and tags
resource "aws_s3_bucket" "data" {
  bucket = "${local.prefix}data"    # "eng-prod-g-api-data"
  tags   = local.tags
}

resource "aws_db_instance" "main" {
  identifier = "${local.prefix}db"  # "eng-prod-g-api-db"
  tags       = local.tags
  # ...
}
```

The labels module is the single source of truth for naming. No resource constructs its own name. No resource defines its own tags. Everything flows from one module invocation.

## The Naming Pattern

### Why Environment Belongs in the Name, Not Just Tags

The environment identifier (`dev`, `prod`) must be part of the resource name, not relegated to metadata. When you run `terraform plan`, the output shows resource names -- not tags. If the environment only exists in a tag, you cannot tell at a glance whether a plan is about to modify a dev resource or a production resource. The environment in the name is an immediate safety signal: `eng-prod-api-db` in a plan output tells you to slow down; `eng-dev-api-db` tells you it is safe to iterate. This distinction saves production outages.

Every resource follows a predictable pattern:

```
<team>-<env>[-<scope>]-<name>[-<function>][-<suffix>]
```

| Component | Required | Purpose | Examples |
|-----------|----------|---------|----------|
| `team` | Yes | Ownership | `eng`, `data`, `plat` |
| `env` | Yes | Environment | `dev`, `prod`, `staging` |
| `scope` | No | Global/regional qualifier | `g` |
| `name` | Yes | Service or project | `api`, `warehouse` |
| `function` | No | Resource purpose | `db`, `cache`, `cluster` |
| `suffix` | No | Resource type hint | `bucket`, `key`, `role` |

### Examples Across Resource Types

```
eng-dev-g-api-db              -- Development API database
eng-prod-g-api-db             -- Production API database
eng-dev-g-warehouse-data      -- Dev data warehouse bucket
plat-prod-g-cicd-runner       -- Production CI/CD runner
data-dev-g-pipeline-queue     -- Dev data pipeline queue
```

When you see any resource name, you immediately know: which team owns it, which environment it belongs to, what service it supports, and what function it serves. No lookup required.

### Name Length Limits

Some cloud resources impose strict name length limits (e.g., IAM roles, Lambda functions, S3 buckets). When the full pattern exceeds the allowed length, drop the optional components (`function`, `suffix`) from the name and move them into tags instead. The required components (`team`, `env`, `name`) stay in the resource name -- they are the minimum for identification. The tags map from the labels module already carries the full context, so nothing is lost.

## Cost Center Validation

The labels module enforces a closed list of valid cost centers. This is not optional. Freeform cost center strings guarantee that three months from now your cost reports contain `compute`, `Compute`, `COMPUTE`, `infra`, and `general` -- all meaning the same thing, none of them queryable.

### The Principle: Define Domains Before Creating Resources

The specific cost centers are always company-specific. A machine learning company has different domains than a fintech or a SaaS platform. What matters is: the list exists, it is closed, and it is enforced at plan time. Define your cost domains in the labels module before the first resource is created. Adding a new domain later is a one-line change with a PR review -- not a free-text field that anyone can fill with anything.

### Good Pattern: Validation at Plan Time

```hcl
variable "cost_center" {
  type        = string
  description = "Cost allocation category. Must be from the approved list."

  validation {
    condition = contains([
      "engineering",      # Application development teams
      "data",             # Data pipelines, analytics, warehousing
      "infrastructure",   # Networking, compute, shared platform
      "security",         # Security tooling, compliance, auditing
      "operations",       # CI/CD, monitoring, operational tooling
    ], var.cost_center)
    error_message = "Invalid cost_center '${var.cost_center}'. Must be from the approved domain list in the labels module."
  }
}
```

The values above are a starting point. Replace them with your company's actual cost domains. The point is not which values you pick -- it is that you pick them explicitly, encode them as a closed list, and reject everything else at plan time.

An invalid cost center is rejected before any resource is created. The engineer sees the error, picks from the list, and moves on. There is no cost center drift.

### Bad Pattern: Freeform Tags After the Fact

```hcl
# DO NOT DO THIS -- no validation, no consistency
resource "aws_instance" "web" {
  tags = {
    CostCenter = "Web Team"   # Freeform string -- who validates this?
    Owner      = "john"       # Person, not team -- what happens when John leaves?
    Env        = "Production" # Capital P -- different from "production" in other resources
  }
}
```

This produces tags that are technically present but practically useless. Cost reports become a manual reconciliation exercise instead of an automated query.

## Required Tags

Every resource must carry these tags, applied automatically by the labels module:

| Tag | Source | Purpose |
|-----|--------|---------|
| `owner` | `var.team` | Team accountability -- who to page when it breaks |
| `environment` | `var.env` | Environment identification -- dev, staging, prod |
| `project` | `var.name` | Service grouping -- which project owns this resource |
| `cost_center` | `var.cost_center` | Financial allocation -- where the bill goes |
| `managed_by` | Hard-coded `"terraform"` | Identifies IaC-managed resources vs. manual |

Additional tags can be merged, but these five are non-negotiable. The labels module produces them automatically. Engineers never type them manually.

## Naming Conventions by Resource Type

Different resource types benefit from different conventions while sharing the same prefix:

### Log Groups (Slash-Separated Hierarchy)

```
/<team>/<env>/<function>[/<subfunction>]

/eng/dev/ecs/cluster
/eng/prod/api/access-logs
/data/prod/pipeline/etl
```

Log groups use slashes instead of dashes because cloud logging consoles render them as navigable trees. This is a deliberate deviation from the dash-based convention -- logs benefit from hierarchy.

### Domains

```
Production:   <service>.mycompany.com
Development:  <service>.dev.mycompany.com
Internal:     <service>.internal
```

### Database Users (Purpose-Based)

```
<purpose>_<access_level>

api_rw           -- API service read-write
dashboard_ro     -- Dashboard read-only
generic_ro       -- Team-wide read access
```

No person-specific database users. Team members use a shared read-only role. Service accounts get purpose-specific credentials managed by a secrets manager.

### Security Groups

```
sg_<scope>_<protocol_or_port>

sg_private_postgres       -- Port 5432 from internal CIDR
sg_private_redis          -- Port 6379 from internal CIDR
sg_public_https           -- Port 443 from 0.0.0.0/0
```

## Lowercase Everything

All naming components are converted to lowercase by the labels module. Mixed case creates silent mismatches: `Prod` and `prod` are different tag values in most cloud providers, different S3 bucket names, and different IAM policy conditions. Enforce lowercase once in the module and never think about it again.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Resource tags | Tags (key-value on resources) | Labels (key-value on resources) | Tags (key-value on resources) |
| Tag enforcement | AWS Config rules, SCPs | Organization Policy constraints | Azure Policy |
| Cost allocation | Cost Explorer + Cost Allocation Tags | Billing Labels | Cost Management + Tags |
| Naming restrictions | Varies by service (S3: 63 chars, lowercase) | Labels: 63 chars, lowercase | Tags: 512 chars key, 256 chars value |
| Tag propagation | Auto-tagging via Terraform `default_tags` | Auto-labeling via Terraform | Tag inheritance from resource groups |
| Compliance scanning | AWS Config (required-tags rule) | Policy Analyzer | Azure Policy (require tag) |

## Examples

Working implementations in `examples/`:
- **`examples/labels-module.md`** -- Complete Terraform labels module with cost center validation, prefix generation, and standard tag map output
- **`examples/labels-usage.md`** -- Practical usage patterns showing how services consume the labels module for naming storage buckets, databases, compute instances, and IAM roles

## Review Checklist

When designing or reviewing naming and tagging:

- [ ] A labels module exists and is the single source of truth for naming
- [ ] Every resource name is constructed from the labels module prefix, not hand-crafted
- [ ] Every resource carries the five required tags (owner, environment, project, cost_center, managed_by)
- [ ] Cost centers are validated against a closed list at `terraform plan` time
- [ ] No freeform tag values exist for owner, environment, or cost_center
- [ ] All naming components are lowercase with no mixed-case values
- [ ] The naming pattern is documented and follows `<team>-<env>[-<scope>]-<name>[-<function>][-<suffix>]`
- [ ] Resource names that exceed provider length limits drop optional components (function, suffix) to tags
- [ ] Log groups use slash-separated hierarchy, not dashes
- [ ] Database users follow the `<purpose>_<access_level>` convention with no personal usernames
- [ ] Domain naming separates environments (`service.dev.company.com` vs. `service.company.com`)
- [ ] New cost centers require an explicit addition to the approved list in the labels module
- [ ] Tag compliance is enforced by cloud provider policy, not just convention
