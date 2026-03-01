---
name: repository-and-state-strategy
description: "This skill should be used when the user is structuring Terraform repositories, deciding between mono-repo and multi-repo strategies, organizing infrastructure into layers, designing state management architecture, setting up cross-layer dependencies, or evaluating blast radius of infrastructure changes. Covers multi-repository strategy, numbered layer architecture, state-per-layer-per-environment isolation, cross-layer remote state references, and deployment ordering."
version: 1.0.0
---

# Monolithic State Is a Ticking Time Bomb

A single Terraform state file that contains your entire infrastructure is a liability disguised as simplicity. One bad `terraform apply` can destroy your network, databases, and compute in a single operation. One state file corruption locks out every team. One slow plan blocks every deployment. The blast radius is everything, and the recovery plan is "restore from backup and pray."

Production infrastructure demands intentional separation -- separate repositories for separate concerns, separate state files for separate layers, and numbered directories that encode dependency order at a glance. This is not premature optimization. It is the difference between an outage that takes down one monitoring dashboard and an outage that takes down your entire platform.

## Multi-Repository Strategy

Infrastructure repositories should be split by **change cadence and ownership**. Organization-level IAM changes happen monthly. Network changes happen quarterly. Service deployments happen daily. Forcing all three through the same repository, the same review process, and the same CI pipeline creates friction where none should exist.

```
REPOSITORIES
|
+-- tf-root                          <-- Organization & IAM management
|   Scope: SSO, permissions, accounts, security delegation
|   Changes: Monthly (new users, permission updates)
|
+-- tf-global-infrastructure         <-- Shared infrastructure per environment
|   Scope: VPCs, security groups, databases, compute clusters, monitoring
|   Structure: Numbered layers (00-90) with env subdirectories
|   Changes: Weekly (new resources, configuration updates)
|
+-- tf-module-labels                 <-- Foundational naming/tagging module
+-- tf-module-alerts                 <-- Monitoring/alerting module
+-- tf-module-container-service      <-- Container orchestration module
|
+-- [per-service repos]              <-- App-specific infrastructure
    Each service manages its own Terraform alongside application code
    Changes: Daily (deployments, scaling, feature flags)
```

**Why separate repos, not directories in a mono-repo?**
- **Access control**: The root repo requires elevated permissions. Service repos do not.
- **CI/CD isolation**: A change to monitoring should not trigger a plan for networking.
- **Review ownership**: The platform team reviews shared infrastructure. Service teams review their own.
- **Change cadence**: Modules evolve on their own release cycle, independent of consumers.

## Numbered Layer Architecture

Within the global infrastructure repository, directories are numbered to encode dependency order. Lower numbers are prerequisites for higher numbers. Numbering in steps of ten (00, 10, 20 ... not 1, 2, 3) reserves space to insert or split layers without renumbering -- if databases grow complex, split `30_databases` into `30_relational` and `35_caches` without touching anything else.

```
tf-global-infrastructure/
+-- 00_network/              <-- VPCs, subnets, Route53, VPN, VPC endpoints
|   +-- dev/
|   +-- prod/
+-- 10_security/             <-- Security groups, IAM roles, KMS, WAF, certificates
|   +-- dev/
|   +-- prod/
+-- 20_storage/              <-- Object storage, file systems
|   +-- dev/
|   +-- prod/
+-- 30_databases/            <-- Relational databases, caches, warehouses
|   +-- dev/
|   +-- prod/
+-- 40_compute/              <-- Container clusters, auto-scaling, GPU instances
|   +-- dev/
|   +-- prod/
+-- 50_edge/                 <-- CDN, load balancers, API gateways
|   +-- prod/
+-- 60_messaging/            <-- Message brokers, event buses, queues
|   +-- dev/
|   +-- prod/
+-- 70_monitoring/           <-- Metrics, dashboards, log aggregation
|   +-- dev/
|   +-- prod/
+-- 80_ci_cd/                <-- Build runners, pipeline infrastructure
+-- 90_shared_services/      <-- Bastion hosts, service discovery
    +-- dev/
    +-- prod/
```

Not every layer needs per-environment subdirectories. Layers like `80_ci_cd` (e.g., self-hosted GitHub runners) are shared infrastructure — there is no reason to duplicate build runners per environment in a startup. Similarly, `50_edge` may only exist in production if there is no dev CDN or load balancer. Only create environment subdirectories where the resources are actually environment-specific.

### Why This Works

| Property | Benefit |
|----------|---------|
| **Dependency encoding** | Layer 40 (compute) cannot exist without layer 00 (network). The numbering makes this obvious. |
| **Independent state** | Each layer has its own state file. A bad apply in monitoring cannot destroy your network. |
| **Independent CI/CD** | Each layer can have its own pipeline. Network changes do not block compute deployments. |
| **Clear mental model** | New engineers understand the dependency graph in seconds, not hours. |
| **Insert and split** | Need to split databases into relational and caches? Insert `35_caches` between 30 and 40 without renumbering anything. |

### Deployment Order

Layers deploy in numerical order. This is the full dependency chain:

```
tf-root (organization setup, SSO, security delegation)
  |
  v
00_network (VPCs, subnets, DNS, VPC endpoints)
  |
  v
10_security (security groups, KMS keys, certificates, WAF)
  |
  v
20_storage (object storage, file systems)
  |
  v
30_databases (relational databases, caches, warehouses)
  |
  v
40_compute (container clusters, auto-scaling groups)
  |
  v
50_edge (CDN distributions, load balancers)
  |
  v
60_messaging (message brokers, event buses, queues)
  |
  v
70_monitoring (metrics collection, dashboards, alerting)
  |
  v
80_ci_cd (build runners)
  |
  v
90_shared_services (bastion hosts, service discovery)
```

Dependencies are strictly forward: a layer may reference any lower-numbered layer via remote state, but never a higher-numbered one. Layer 50 can read from layers 00, 10, or 40 -- but layer 50 cannot depend on layer 60. This ensures the deployment chain is always acyclic and any layer can be planned or applied without waiting for higher layers to exist.

## State Management: One State File Per Layer Per Environment

The cardinal rule of Terraform state management: **every layer in every environment gets its own state file**. No exceptions. No "we will split it later." Split it now.

### State Bucket Strategy

```
One state bucket per cloud account (state buckets use <org>-<env>-tfstate as an exception
to the labels module naming -- they are account-global and need globally unique names):
  myorg-root-tfstate         <-- Root/management account
  myorg-security-tfstate     <-- Security account
  myorg-log-archive-tfstate  <-- Log archive account
  myorg-dev-tfstate          <-- Development account
  myorg-prod-tfstate         <-- Production account
```

Within each bucket, one key per layer or service:

```
myorg-dev-tfstate/
  network              <-- 00_network/dev state
  security             <-- 10_security/dev state
  storage              <-- 20_storage/dev state
  databases            <-- 30_databases/dev state
  compute              <-- 40_compute/dev state
  messaging            <-- 60_messaging/dev state
  monitoring           <-- 70_monitoring/dev state
  shared_services      <-- 90_shared_services/dev state
  myapp-api            <-- Service-owned state (separate repo)
  billing-service      <-- Service-owned state (separate repo)
```

### State Properties (Non-Negotiable)

Every state bucket must have all four:

| Property | Setting | Why |
|----------|---------|-----|
| **Encryption** | AES-256 server-side | State contains secrets (database passwords, API keys) |
| **Versioning** | Enabled | Recover from accidental state corruption or deletion |
| **Locking** | Enabled | Prevent concurrent applies that corrupt state |
| **Public access** | Blocked | State files are the keys to your kingdom |

### Cross-Layer State References

Higher layers read outputs from lower layers using remote state data sources. This creates explicit, auditable dependency chains.

```hcl
# 40_compute/dev/main.tf -- Compute reads from network and security

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "network"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "security"
    region = "eu-west-1"
  }
}

locals {
  vpc_id          = data.terraform_remote_state.network.outputs.vpc_id
  private_subnets = data.terraform_remote_state.network.outputs.private_subnets
  base_sg_ids     = data.terraform_remote_state.security.outputs.base_security_group_ids
}
```

**Dependency chain in practice:**
- `compute` reads from `network` + `security`
- `databases` reads from `network` + `security`
- `monitoring` reads from `compute` + `network`
- `shared_services` reads from `network`
- `edge` reads from `compute` + `security`

## Good vs. Bad Patterns

**Bad: Monolithic state file**
```
myorg-dev-tfstate/
  everything          <-- One state file for ALL infrastructure
```
Problems: blast radius is everything. One bad apply can destroy networking, databases, and compute simultaneously. Plans take minutes as Terraform refreshes hundreds of resources. Two engineers cannot work on different layers in parallel.

**Good: State per layer per environment**
```
myorg-dev-tfstate/
  network             <-- 42 resources, 15-second plan
  security            <-- 28 resources, 10-second plan
  databases           <-- 15 resources, 8-second plan
  compute             <-- 35 resources, 12-second plan
```
Benefits: blast radius limited to one layer. Plans are fast. Engineers work on different layers in parallel. Recovery from corruption affects only one layer.

**Bad: Environment state mixed together**
```hcl
# One state file contains both dev and prod resources
resource "aws_vpc" "dev" { cidr_block = "10.0.0.0/16" }
resource "aws_vpc" "prod" { cidr_block = "10.1.0.0/16" }
```
Problems: a mistake in dev configuration can destroy prod resources. No way to restrict who can modify prod without restricting dev.

**Good: Separate directories, separate state, separate permissions**
```
00_network/
  dev/   -> myorg-dev-tfstate/network
  prod/  -> myorg-prod-tfstate/network
```

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| State backend | S3 bucket (`use_lockfile`) | GCS bucket (native locking) | Azure Blob Storage + lease locking |
| State encryption | AES-256 SSE-S3 or SSE-KMS | Default encryption (Google-managed or CMEK) | Storage Service Encryption (Microsoft-managed or CMK) |
| State locking | S3 native locking (`use_lockfile = true`) | GCS native locking | Blob lease locking |
| Remote state reference | `terraform_remote_state` with S3 backend | `terraform_remote_state` with GCS backend | `terraform_remote_state` with azurerm backend |
| Account isolation | AWS accounts via Organizations | GCP projects via folders | Azure subscriptions via Management Groups |
| State bucket per account | One S3 bucket per AWS account | One GCS bucket per GCP project | One Storage Account per Azure subscription |

## Examples

Working implementations in `examples/`:
- **`examples/numbered-layer-layout.md`** -- Complete directory structure for a global infrastructure repository with numbered layers, environment subdirectories, and backend configuration for each layer
- **`examples/cross-layer-state-references.md`** -- Terraform configurations showing how the compute layer reads outputs from network and security layers via remote state, including the backend configuration and output definitions

## Review Checklist

When designing or reviewing repository and state architecture:

- [ ] Infrastructure is split across repositories by change cadence and ownership (root, global, modules, services)
- [ ] The global infrastructure repository uses numbered layers (00, 10, 20...) that encode dependency order
- [ ] Gap numbering is used (increments of 10) to allow future layer insertion without renumbering
- [ ] Every layer has a separate directory per environment (`dev/`, `prod/`)
- [ ] Every layer in every environment has its own state file (one state key per layer per environment)
- [ ] State buckets have encryption, versioning, locking, and public access blocking enabled
- [ ] Cross-layer dependencies use `terraform_remote_state` data sources, not hardcoded values
- [ ] The dependency chain flows downward only -- higher-numbered layers read from lower-numbered layers, never the reverse
- [ ] Service repositories have their own state keys, separate from infrastructure layers
- [ ] No state file contains resources from multiple environments
- [ ] State bucket naming follows a consistent convention (`<org>-<env>-tfstate`)
- [ ] The deployment order is documented and matches the numerical layer ordering
