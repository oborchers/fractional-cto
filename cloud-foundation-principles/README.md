# cloud-foundation-principles

A Claude Code plugin that codifies robust cloud infrastructure foundations — research-backed, opinionated guidance drawn from production experience scaling cloud infrastructure across multiple migrations, hundreds of services, and teams of every size.

## What It Does

When Claude is working on cloud infrastructure — account structure, Terraform organization, networking, security, deployment pipelines, or any of the patterns below — the relevant principle skill activates automatically and guides the work with specific, actionable rules and review checklists.

This plugin provides **principles and examples, not boilerplate.** It tells Claude *what* to build and *why*, with Terraform/HCL patterns showing *how*. Principles are cloud-agnostic with provider-specific translation tables (AWS, GCP, Azure) where applicable.

## The 15 Principles

| # | Principle | Skill | What It Covers |
|---|-----------|-------|----------------|
| I | Isolate everything from day one | `multi-account-from-day-one` | Account structure, environment isolation, landing zones, organization units |
| II | Name it in code or lose it forever | `naming-and-labeling-as-code` | Labels module, naming conventions, cost centers, tag enforcement at plan time |
| III | Document every decision or relitigate it forever | `architecture-decision-records` | Numbered ADRs, exemption documentation, immutable decision history |
| IV | Layer your repositories and state | `repository-and-state-strategy` | Multi-repo strategy, numbered layers, state-per-layer isolation, blast radius containment |
| V | Build modules that enforce guardrails | `terraform-module-patterns` | Wrapping community modules, smart defaults, validation, version pinning, conditional creation |
| VI | Design the network before the first resource | `network-architecture` | VPC/VNet design, subnet tiers, API gateways, DNS, private connectivity |
| VII | No keys, no passwords, no exceptions | `zero-static-credentials` | SSO for humans, OIDC for CI/CD, session-based instance access |
| VIII | Security monitoring ships with the infrastructure | `security-monitoring-from-day-one` | Centralized threat detection, compliance scanning, delegated security account |
| IX | Separate secrets from configuration | `secrets-and-configuration-management` | Credential rotation, config values, access patterns, secret hierarchy |
| X | Rent, don't build | `managed-services-over-self-hosted` | Managed vs self-hosted, container orchestration, workflow engines, databases |
| XI | Every service owns its infrastructure | `service-owned-infrastructure` | Service-owned Terraform, shared modules, no central platform bottleneck |
| XII | Tag every image with its commit | `container-image-tagging` | Git SHA traceability, registry lifecycle policies, OCI labels, no "latest" |
| XIII | Release with intention | `tag-based-production-deploys` | Git tag releases, manual approval gates, pipeline stages, pre-commit hooks |
| XIV | One pipeline platform, no exceptions | `unified-cicd-platform` | Platform consolidation, OIDC authentication, eliminating multi-provider burden |
| XV | Leave it cleaner than you found it | `operational-hygiene` | Resource cleanup, cost attribution, monitoring, drift detection |

## Installation

### Claude Code (via fractional-cto Marketplace)

```bash
# Register the marketplace (once)
/plugin marketplace add oborchers/fractional-cto

# Install the plugin
/plugin install cloud-foundation-principles@fractional-cto
```

### Local Development

```bash
# Test directly with plugin-dir flag
claude --plugin-dir /path/to/fractional-cto/cloud-foundation-principles
```

## Components

### Skills (16)

One meta-skill (`using-cloud-foundation-principles`) that provides the index and 15 principle skills that activate automatically when Claude detects relevant cloud infrastructure patterns.

Each skill includes:
- Battle-tested principles with cited rationale
- Good/bad examples with concrete Terraform/HCL code
- Cloud provider translation tables (AWS, GCP, Azure)
- Actionable review checklists

### Command (1)

- `/cloud-foundation-principles:cloud-foundation-review` — Review the current infrastructure code against all relevant cloud foundation principles

### Agent (1)

- `cloud-foundation-reviewer` — Comprehensive infrastructure audit agent that evaluates code against all 15 principles with severity-rated findings

### Hook (1)

- `SessionStart` — Injects the skill index at the start of every session so Claude knows the principles are available

## The Three Meta-Principles

All fifteen principles rest on three foundations:

1. **Governance before infrastructure** — Naming conventions, account structure, and decision records must exist before the first resource is created
2. **Everything in code, no exceptions** — Infrastructure not in code is a liability. Every resource, every permission, every configuration must be version-controlled
3. **Prevent day-1 mistakes that become day-100 catastrophes** — Some decisions are cheap on day one and catastrophically expensive later. This plugin ensures you make them on day one

## License

MIT
