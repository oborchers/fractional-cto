---
name: multi-account-from-day-one
description: "This skill should be used when the user is setting up a new cloud project, designing account or project structure, creating environment isolation, configuring organization units or management groups, implementing landing zones, or deciding how to separate dev and prod workloads. Covers multi-account strategy, blast radius isolation, landing zone setup, and organizational governance."
version: 1.0.0
---

# Separate Accounts Before You Write a Single Resource

Running development and production in a single cloud account is the most common shortcut in early-stage infrastructure, and it is cheap to fix on day one -- one afternoon of work. Six months later, when production databases share IAM policies with developer sandboxes, when billing is an undifferentiated blob, and when a misconfigured dev deployment takes down prod, the fix becomes a full migration measured in weeks. Multi-account isolation is not a scale concern. It is a day-one concern.

## Why Single-Account Fails

A single cloud account creates invisible couplings that compound over time:

| Problem | Single Account | Multi-Account |
|---------|---------------|---------------|
| **Blast radius** | A dev IAM policy change can affect prod resources | Accounts are hard boundaries; dev cannot touch prod |
| **Billing** | All costs in one bucket; cost attribution requires tagging discipline | Per-account billing is automatic and unambiguous |
| **Permissions** | Everyone who can deploy to dev can potentially access prod secrets | Cross-account access requires explicit trust policies |
| **Service quotas** | Dev load tests consume prod quota | Each account has independent quotas |
| **Compliance** | Auditors must review everything; no clean scope boundary | Prod account is the audit scope; dev is excluded |
| **Credential blast** | One leaked key exposes everything | One leaked key exposes one environment |

The longer you wait, the worse each problem gets. Resources accumulate. IAM policies intertwine. Developers build tooling that assumes a single account. Every day you delay makes the eventual migration more expensive.

## The Minimum Viable Account Structure

Start with six accounts or projects. This is the minimum that provides meaningful isolation:

```
Organization Root
├── Management Account          -- SSO, billing, organization policies
│
├── Security OU                 -- (GCP: Folder, Azure: Management Group)
│   ├── security                -- Centralized security services
│   └── log-archive             -- Immutable, centralized audit logs
│
├── Sandbox OU
│   └── sandbox                 -- Unrestricted experimentation, no prod access
│
└── Workloads OU
    ├── dev                     -- Development workloads
    └── prod                    -- Production workloads
```

Six accounts. One afternoon. This gives you environment isolation, a dedicated security boundary, centralized audit logging, a safe experimentation space, and clean billing separation from day one. All three major cloud providers (AWS Control Tower, GCP Cloud Foundation Toolkit, Azure Landing Zones) include a centralized logging account by default.

### When to Add More Accounts

As your team and workloads grow, expand the structure:

| Account | Add When | Purpose |
|---------|----------|---------|
| `cicd` | You adopt self-hosted runners | Isolate CI/CD compute from application workloads |
| `staging` | You need a prod-like pre-release env | Full production mirror for release validation |
| `data` or `ml-training` | GPU or large data workloads | Isolate expensive compute with separate quotas and billing |

Do not create person-specific accounts. Use team-based identities and shared accounts with role-based access. Person-specific accounts create credential sprawl and make offboarding a security risk.

## Landing Zones: Automate Account Governance

Manually creating accounts and configuring guardrails does not scale past three accounts. Use your cloud provider's landing zone tooling to automate account provisioning, enforce baseline policies, and centralize governance.

A landing zone provides:
- **Automated account provisioning** with baseline security configuration
- **Guardrails** (preventive and detective) applied organization-wide
- **Centralized logging** routed to a dedicated log archive
- **Identity federation** configured once, inherited by all accounts

### Good Pattern: Landing Zone with Guardrails

```hcl
# Organization structure -- Terraform manages the hierarchy
resource "cloud_organization" "root" {
  feature_set = "ALL"
}

resource "cloud_organizational_unit" "security" {
  name      = "Security"
  parent_id = cloud_organization.root.roots[0].id
}

resource "cloud_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = cloud_organization.root.roots[0].id
}

resource "cloud_organizational_unit" "workloads_prod" {
  name      = "Production"
  parent_id = cloud_organizational_unit.workloads.id
}

resource "cloud_organizational_unit" "workloads_dev" {
  name      = "Development"
  parent_id = cloud_organizational_unit.workloads.id
}
```

### Bad Pattern: Everything in One Account with Tags

```hcl
# DO NOT DO THIS -- "environment" tags are not isolation boundaries
resource "cloud_instance" "web" {
  instance_type = "t3.micro"
  tags = {
    Environment = "prod"   # This tag does NOT prevent dev from touching it
  }
}

resource "cloud_instance" "web_dev" {
  instance_type = "t3.micro"
  tags = {
    Environment = "dev"    # Same account, same IAM, same blast radius
  }
}
```

Tags are metadata, not security boundaries. An IAM policy that grants `ec2:*` in a single account grants it to both "prod" and "dev" tagged resources. Only account-level separation provides true isolation.

## Identity and Access Across Accounts

Centralize identity in the management account. Federate from an external identity provider (Google Workspace, Okta, Microsoft Entra ID) so that disabling a person in the IdP immediately revokes all cloud access.

### Three Permission Tiers

| Tier | Dev/Sandbox Access | Prod Access | Assigned To |
|------|-------------------|-------------|-------------|
| **Admin** | Full | Full (time-boxed) | Platform team (2-3 people) |
| **Developer** | Full | Read-only + targeted exceptions | Engineering team |
| **Auditor** | Read-only | Read-only | Compliance, external auditors |

Developers should have full access in dev and sandbox but only read-only access in production. Targeted exceptions allow specific actions like viewing logs, connecting to debugging sessions, or reading container registries. No one should have permanent write access to production -- use time-boxed elevated access for incident response.

## CI/CD Authentication: No Static Credentials

CI/CD pipelines authenticate to each account via workload identity federation (OIDC), not static API keys. Each account has its own CI/CD role with a trust policy restricting which repositories can assume it. This means zero stored secrets in your CI/CD system -- no API keys to rotate, no credentials to leak.

The multi-account angle: every account needs its own OIDC role. The trust policy in the dev account allows broader repository access (any branch), while the production account restricts to tag refs only (see the `tag-based-production-deploys` skill for the tag-driven deployment model). For the complete OIDC setup (provider configuration, trust policies, subject claim restrictions, per-provider Terraform), see the `zero-static-credentials` skill.

## Account Email Convention

Use distribution lists or group aliases for account root emails, never personal addresses:

```
cloud-management@mycompany.com     -- Management/root account
cloud-security@mycompany.com       -- Security account
cloud-log-archive@mycompany.com    -- Log archive account
cloud-sandbox@mycompany.com        -- Sandbox account
cloud-dev@mycompany.com            -- Development account
cloud-prod@mycompany.com           -- Production account
```

Personal email addresses tied to accounts create single points of failure. When that person leaves, account recovery becomes a support ticket nightmare.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Organization hierarchy | Organizations + OUs | Organization + Folders | Management Groups |
| Landing zone automation | Control Tower | Cloud Foundation Toolkit | Azure Landing Zones (CAF) |
| Account/project creation | AWS Account Factory | Project Factory | Subscription vending |
| Guardrails / policies | Service Control Policies (SCPs) | Organization Policies | Azure Policy |
| Centralized identity | IAM Identity Center (SSO) | Cloud Identity + Workforce IdF | Microsoft Entra ID |
| Cross-account roles | IAM Roles + trust policies | Service account impersonation | Managed Identity + RBAC |
| Billing isolation | Per-account billing | Per-project billing | Per-subscription billing |
| Security delegation | Delegated administrator | Organization-level security | Microsoft Defender for Cloud |

## Examples

Working implementations in `examples/`:
- **`examples/organization-structure.md`** -- Terraform module that creates a six-account organization with OUs, account email conventions, and baseline policies
- **`examples/cross-account-roles.md`** -- Terraform configuration for CI/CD OIDC federation and developer cross-account access with least-privilege permissions

## Review Checklist

When designing or reviewing cloud account structure:

- [ ] Dev and prod workloads run in separate accounts or projects, never co-located
- [ ] A dedicated security account exists for centralized security services
- [ ] A dedicated log-archive account exists for immutable, centralized audit logs
- [ ] A sandbox account exists for unrestricted experimentation, isolated from dev and prod
- [ ] The management/root account contains no application workloads
- [ ] Landing zone automation is used for account provisioning and guardrails
- [ ] Account root emails use team distribution lists, not personal addresses
- [ ] Identity is federated from an external IdP, not managed natively in the cloud provider
- [ ] Developers have full access in dev but read-only access in prod
- [ ] CI/CD uses OIDC federation per account, not static credentials
- [ ] No person-specific accounts exist; all accounts are team-based
- [ ] Each account has independent state files and deployment pipelines
- [ ] Service quotas are monitored per account to prevent cross-environment interference
- [ ] Billing is reviewable per account without relying solely on tags
