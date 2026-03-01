# The First Three ADRs

Every infrastructure project should start with these three ADRs before creating any cloud resources. They establish the governance foundation that everything else builds on.

## ADR-0001: Adopt Architecture Decision Records

```markdown
# ADR-0001: Adopt Architecture Decision Records

**Status:** Accepted
**Date:** 2026-01-10
**Deciders:** Platform Team

## Context

Our team is building cloud infrastructure from scratch. Decisions made in the
first weeks (cloud provider, account structure, naming conventions, CI/CD
approach) will shape the project for years. Without a record of these
decisions, we will:

- Relitigate settled decisions when new team members join
- Forget the constraints that led to a specific choice
- Make contradictory decisions as the team grows
- Lose institutional knowledge when team members leave

We need a lightweight documentation practice that captures decisions without
creating bureaucratic overhead.

## Decision

Adopt Architecture Decision Records (ADRs) for all significant infrastructure
decisions. Each ADR follows a standard format (Context, Decision, Consequences),
is numbered sequentially, and is stored in version control alongside the
infrastructure code.

ADRs are immutable once accepted. Changed decisions result in new ADRs that
supersede the original.

An ADR is warranted when:
- The decision would take >10 minutes to explain to a new team member
- Reverting the decision would take >1 day of work
- Multiple reasonable alternatives exist and we need to record why we chose one

## Consequences

### Positive
- New team members can read ADRs to understand all past decisions
- Decisions are never relitigated without new information
- The ADR index serves as a project history and onboarding guide

### Negative
- Requires discipline to write ADRs in the moment (15 minutes per decision)
- Risk of ADR fatigue if applied to trivial decisions

### Follow-Up Actions
- [ ] Create ADR directory in the infrastructure repository
- [ ] Write ADR-0002 (naming convention) and ADR-0003 (account structure)
- [ ] Add ADR index (README.md) to the ADR directory
```

## ADR-0002: Naming Convention and Labels Module

```markdown
# ADR-0002: Naming Convention and Labels Module

**Status:** Accepted
**Date:** 2026-01-10
**Deciders:** Platform Team

## Context

Every cloud resource needs a name and tags. Without a convention established
before the first resource is created, names will be inconsistent, tags will
be incomplete, and cost attribution will be impossible to reconstruct.

Retrofitting a naming convention after resources exist requires renaming (which
often means destroying and recreating resources), updating all references, and
coordinating across every team that creates resources. This is orders of
magnitude more expensive than establishing the convention on day one.

We considered:
- Freeform naming with guidelines in a wiki (rejected: unenforceable)
- Cloud-provider tag policies only (rejected: does not cover resource names)
- A Terraform labels module with validation (selected)

## Decision

All cloud resources follow the naming pattern:
  <team>-<env>[-<scope>]-<name>[-<function>][-<suffix>]

A Terraform labels module (tf-module-labels) is the first module built. It:
- Takes team, environment, name, cost_center, and optional scope as inputs
- Outputs a name prefix and a standard tags map
- Validates cost_center against a closed list of approved values
- Rejects invalid inputs at terraform plan time

Every Terraform project imports the labels module once. Every resource uses
its prefix and tags outputs. No resource constructs its own name or defines
its own tags.

## Consequences

### Positive
- Every resource name is predictable: knowing team + env + name is enough
- Cost center attribution is automatic and validated
- Invalid names and cost centers are caught before any resource is created
- All resources are queryable by owner, environment, project, and cost center

### Negative
- The labels module must be created before any other infrastructure
- Adding a new cost center requires a module update and release
- All teams must agree on the naming pattern (forces alignment early)

### Follow-Up Actions
- [ ] Create tf-module-labels repository
- [ ] Define initial cost center list with finance/leadership
- [ ] Publish v1.0.0 of the labels module
- [ ] Update all existing Terraform projects to import the module
```

## ADR-0003: Multi-Account Strategy

```markdown
# ADR-0003: Multi-Account Strategy

**Status:** Accepted
**Date:** 2026-01-12
**Deciders:** Platform Team

## Context

We are starting a new cloud project and must decide whether to use a single
account/project or multiple accounts/projects for environment isolation.

Single-account risks:
- A dev IAM misconfiguration can affect production resources
- Billing is undifferentiated; cost attribution relies entirely on tags
- Service quotas are shared; a dev load test can exhaust prod quota
- Compliance audit scope includes all environments

Multi-account costs:
- One afternoon of setup (organization, OUs, 6 accounts)
- Slightly more complex CI/CD (per-account roles)
- Cross-account access requires explicit configuration

The cost of multi-account setup is fixed and small. The cost of migrating
from single-account to multi-account grows every day as resources accumulate.

## Decision

Use a multi-account strategy with a minimum of six accounts:

1. Management account -- Organization management, SSO, billing
2. Security account -- Centralized security services (delegated admin)
3. Log-archive account -- Immutable, centralized audit logs
4. Sandbox account -- Unrestricted experimentation, isolated from dev and prod
5. Dev account -- Development workloads
6. Prod account -- Production workloads

Additional accounts (cicd, staging) will be added as needs arise.

Accounts are organized into OUs:
- Security OU: security and log-archive accounts
- Sandbox OU: sandbox account
- Workloads OU: dev and prod accounts (in sub-OUs)

Identity is federated from an external IdP. CI/CD uses OIDC federation with
per-account roles. No static credentials exist anywhere.

## Consequences

### Positive
- Hard isolation between dev and prod (IAM, networking, quotas, billing)
- Per-account billing provides automatic cost visibility per environment
- Compliance audit scope is limited to the prod account
- Blast radius of any misconfiguration is limited to one account

### Negative
- Initial setup takes ~4 hours (one-time cost)
- CI/CD must configure OIDC trust per account
- Cross-account access patterns require explicit terraform configuration
- Landing zone tooling has a learning curve

### Follow-Up Actions
- [ ] Set up cloud organization with landing zone automation
- [ ] Create the six initial accounts with team email aliases
- [ ] Configure SSO with external identity provider
- [ ] Set up OIDC federation for CI/CD in each account
- [ ] Document the account structure in the infrastructure README
```

## ADR Index

After writing these three ADRs, create an index file:

```markdown
# Architecture Decision Records

| # | Title | Status | Date |
|---|-------|--------|------|
| ADR-0001 | Adopt Architecture Decision Records | Accepted | 2026-01-10 |
| ADR-0002 | Naming Convention and Labels Module | Accepted | 2026-01-10 |
| ADR-0003 | Multi-Account Strategy | Accepted | 2026-01-12 |
```

Every new ADR gets a row in this table. This is the first thing new team members read.
