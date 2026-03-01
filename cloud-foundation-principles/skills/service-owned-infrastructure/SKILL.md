---
name: service-owned-infrastructure
description: "This skill should be used when the user is deciding where infrastructure code should live, structuring service repositories with Terraform, separating shared vs service-owned resources, designing module consumption patterns, or eliminating centralized deployment bottlenecks. Covers service-owned IaC directories, remote state consumption, shared module guardrails, and the boundary between platform and service infrastructure."
version: 1.0.0
---

# The Team That Builds It Should Deploy It

Every week a service team waits for a central platform team to provision a load balancer, create a DNS record, or update a task definition is a week of velocity lost. The bottleneck is never technical -- it is organizational. When infrastructure lives in a central repository owned by a separate team, every deployment becomes a ticket, every ticket becomes a queue, and every queue becomes a reason to cut corners. Service-owned infrastructure eliminates this bottleneck by placing infrastructure definitions alongside the application code they serve.

This does not mean every team reinvents networking from scratch. It means the platform team provides modules and standards; service teams consume them. The platform team builds the highway. Service teams drive on it.

## The Repository Pattern

Each service repository contains its own `infrastructure/` directory with per-environment Terraform configurations alongside the application code. This is the foundational layout:

```
myapp-api/
├── src/                        # Application code
├── Dockerfile                  # Container image definition
├── infrastructure/
│   ├── dev/
│   │   ├── main.tf             # Labels module, remote state references
│   │   ├── service.tf          # Container service definition
│   │   ├── database.tf         # Service-specific database (if needed)
│   │   ├── loadbalancer.tf     # Target groups, listener rules
│   │   ├── registry.tf         # Container registry repository
│   │   ├── secrets.tf          # Secrets Manager entries
│   │   ├── alerts.tf           # Monitoring alarms
│   │   └── backend.tf          # Remote state backend configuration
│   └── prod/
│       └── ...same structure, different values
└── .github/workflows/          # CI/CD pipelines (or .gitlab-ci.yml, etc.)
    ├── ci.yml
    └── cd.yml
```

The critical insight: **application code and infrastructure code are versioned together, reviewed together, and deployed together**. When a developer changes the container definition, they update the task definition in the same pull request. When a service needs a new secret, the Secrets Manager entry is added in the same commit that references it.

## Shared vs. Service-Owned: Drawing the Line

Not everything belongs in the service repository. The line is clear:

| Shared (Platform Team Owns) | Service-Owned (Service Team Owns) |
|------------------------------|-----------------------------------|
| VPC, subnets, route tables | Load balancer target groups, listener rules |
| Security groups (base set) | Service-specific security group rules |
| Container cluster | Task/pod definitions, service configuration |
| DNS zones | DNS records for the service |
| Certificate authority / wildcards | N/A (consume shared certificates) |
| Monitoring stack (Prometheus, Grafana) | Service-specific alerts and dashboards |
| Shared databases (data warehouse) | Service-specific operational databases |
| Container registry (the registry itself) | Container repositories (per-service image repos) |
| CI/CD runners | CI/CD pipeline definitions |

**The rule**: if changing it could affect multiple services, it is shared. If it only affects one service, that service owns it.

## Consuming Shared Infrastructure

Services read from the shared infrastructure layer via remote state references (the same cross-layer pattern defined in the `repository-and-state-strategy` skill). The service never modifies shared resources -- it only reads their outputs.

```hcl
# infrastructure/dev/main.tf

# Every service starts with the labels module for consistent naming
module "labels" {
  source  = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team    = "platform"
  env     = "dev"
  name    = "myapp-api"
}

# Read shared networking outputs
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "network"
    region = "eu-west-1"
  }
}

# Read shared security outputs
data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "security"
    region = "eu-west-1"
  }
}

# Read shared compute outputs
data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "compute"
    region = "eu-west-1"
  }
}
```

Consumed outputs typically include: `vpc_id`, `private_subnets`, `public_subnets`, `database_subnet_group_name`, `container_cluster_arn`, `base_security_group_ids`, `wildcard_certificate_arn`, `dns_zone_id`, and `internal_dns_zone_id`.

## Good vs. Bad Patterns

**Bad: Central infrastructure repository owns everything**
```
tf-global-infrastructure/
├── services/
│   ├── myapp-api/          # Platform team maintains this
│   ├── billing-service/    # Platform team maintains this
│   ├── auth-service/       # Platform team maintains this
│   └── ...50 more services
```
Problems: every service change requires a PR to the platform repo. Platform team becomes a bottleneck. Service teams cannot deploy independently. Blast radius of a bad apply covers all services.

**Good: Service repositories own their infrastructure**
```
myapp-api/infrastructure/          # myapp team owns this
billing-service/infrastructure/    # billing team owns this
auth-service/infrastructure/       # auth team owns this
```
Benefits: independent deployments, clear ownership, blast radius limited to one service, infrastructure changes reviewed by the team that understands the service.

**Bad: Copy-paste raw resource definitions across services**
```hcl
# Every service re-implements container service from scratch
resource "aws_ecs_service" "this" {
  # 80 lines of configuration, slightly different in each repo
  # No consistency, no shared defaults, bugs fixed in one place but not others
}
```

**Good: Consume shared modules with opinionated defaults**
```hcl
# Every service uses the same module, overriding only what differs
module "service" {
  source  = "git::https://github.com/myorg/tf-module-container-service.git?ref=v2.1.0"
  name    = module.labels.prefix
  cluster = data.terraform_remote_state.compute.outputs.cluster_arn
  image   = "${local.registry}/${local.image_name}:${var.image_tag}"
  cpu     = 1024
  memory  = 2048

  health_check_path = "/health"
  desired_count     = 2
}
```

## The Shared Module Contract

Platform teams provide shared modules that encode organizational standards. These modules are the guardrails -- they ensure consistency without requiring central control over every deployment.

A well-designed shared module:
- **Wraps community modules** rather than reimplementing (compose around `terraform-aws-modules`, not rebuild)
- **Provides sensible defaults** so services need minimal configuration
- **Validates inputs at the boundary** using `contains()` checks and clear error messages
- **Is versioned with git refs** (`?ref=v2.1.0`) so services pin to known-good versions
- **Injects infrastructure concerns automatically** (naming prefixes, standard tags, monitoring hooks)

```hcl
# Shared module: tf-module-container-service
# Service teams never need to think about deployment circuit breakers,
# rolling update configuration, or health check defaults -- the module
# handles it.

variable "enable_circuit_breaker" {
  type    = bool
  default = true  # Safe default, override if needed
}

variable "deployment_maximum_percent" {
  type    = number
  default = 200  # Rolling updates with zero downtime
}

variable "deployment_minimum_healthy_percent" {
  type    = number
  default = 100  # Never drop below current capacity
}
```

## State Isolation

Each service has its own state file in the shared state bucket. This limits the blast radius of any single `terraform apply` to one service in one environment.

```hcl
# infrastructure/dev/backend.tf
terraform {
  backend "s3" {
    bucket = "myorg-dev-tfstate"
    key          = "myapp-api"        # One key per service
    region       = "eu-west-1"
    use_lockfile = true
  }
}
```

State key naming convention: use the service name. The shared infrastructure layers use descriptive keys (`network`, `security`, `compute`). Service keys use the service name (`myapp-api`, `billing-service`). Never put multiple services in one state file.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Container cluster (shared) | ECS Cluster | GKE Cluster / Cloud Run | AKS Cluster / Container Apps Environment |
| Task/service definition (service-owned) | ECS Task Definition + Service | Cloud Run Service / GKE Deployment | AKS Deployment / Container App |
| Container registry (shared) | ECR (the registry) | Artifact Registry (the registry) | ACR (the registry) |
| Container repository (service-owned) | ECR Repository (per-image) | Artifact Registry Repository | ACR Repository |
| State backend | S3 (`use_lockfile`) | GCS | Azure Blob Storage |
| Remote state reference | `terraform_remote_state` (S3) | `terraform_remote_state` (GCS) | `terraform_remote_state` (azurerm) |
| Secrets storage | Secrets Manager | Secret Manager | Key Vault |
| Load balancer rules (service-owned) | ALB Target Group + Listener Rule | URL Map Backend Service | App Gateway Backend Pool |
| DNS record (service-owned) | Route53 Record | Cloud DNS Record | Azure DNS Record |

## Examples

Working implementations in `examples/`:
- **`examples/service-repository-layout.md`** -- Complete Terraform configuration for a service repository consuming shared infrastructure, including remote state references, container service definition, and state backend setup
- **`examples/shared-module-contract.md`** -- A shared container service module that encodes organizational standards (naming, deployment strategy, health checks) while allowing service-level overrides

## Review Checklist

When designing or reviewing service-owned infrastructure:

- [ ] Service repository contains `infrastructure/dev/` and `infrastructure/prod/` directories alongside application code
- [ ] All shared resources (VPC, cluster, base security groups) are consumed via remote state, never duplicated
- [ ] Service-specific resources (task definitions, load balancer rules, DNS records, alerts) are defined in the service repo
- [ ] Shared modules are consumed with pinned git refs (`?ref=v2.1.0`), not `main` or `latest`
- [ ] Each service has its own state file (one state key per service per environment)
- [ ] The labels module is imported in every service for consistent naming and tagging
- [ ] No service modifies shared infrastructure -- it only reads outputs
- [ ] Infrastructure changes are reviewed by the team that owns the service, not a central team
- [ ] New services can be deployed without filing a ticket to the platform team
- [ ] Module defaults encode organizational standards (deployment strategy, health checks, monitoring)
- [ ] Service teams can override module defaults when justified, but the defaults are production-safe
- [ ] The boundary between shared and service-owned is documented and understood by all teams
