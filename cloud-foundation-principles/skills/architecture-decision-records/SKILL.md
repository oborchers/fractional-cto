---
name: architecture-decision-records
description: "This skill should be used when the user is making significant infrastructure decisions, documenting architectural choices, creating decision records, tracking exemptions from IaC, establishing decision-making processes, or onboarding new team members to existing infrastructure. Covers ADR format, numbering, status lifecycle, exemption tracking, and decision governance."
version: 1.0.0
---

# Write Down Every Decision or Pay to Re-Make It

Every infrastructure team makes dozens of significant decisions in the first months of a project: which cloud provider, which account structure, which naming convention, which container orchestrator, which CI/CD pipeline design. When those decisions live only in Slack threads and the memories of people who were in the room, they get relitigated every time someone new joins, every time someone forgets, and every time a stakeholder asks "why did we do it this way?" An Architecture Decision Record (ADR) takes 15 minutes to write and saves weeks of repeated debates. The format is deliberately simple: context, decision, consequences. No templates longer than a page. No approval workflows. Just a numbered, immutable document stored alongside the code it governs.

This skill follows the lightweight ADR format introduced by Michael Nygard in "Documenting Architecture Decisions" (2011) and later adopted by Thoughtworks in the "Adopt" category of their Technology Radar.

## The ADR Format

An ADR captures exactly four things: what number it is, what context motivated the decision, what was decided, and what the consequences are. Nothing more.

```markdown
# ADR-0001: [Title of the Decision]

**Status:** Proposed | Accepted | Superseded by ADR-XXXX | Deprecated
**Date:** 2026-02-15
**Deciders:** Platform Team

## Context
[What situation, constraint, or question prompted this decision?
What alternatives were considered? What trade-offs exist?]

## Decision
[What was decided? Be specific and unambiguous.
State the choice, not the rationale -- that belongs in Context.]

## Consequences
[What are the positive and negative outcomes of this decision?
What follow-up actions are required?
What becomes easier? What becomes harder?]
```

That is the entire format. Three sections. One page. Fifteen minutes. The value compounds over every month the project exists.

## Numbering and Immutability

ADRs are numbered sequentially: `ADR-0001`, `ADR-0002`, `ADR-0003`. Numbers are never reused, never reordered, and never deleted. An ADR is a historical record of a decision made at a point in time.

### Status Lifecycle

| Status | Meaning |
|--------|---------|
| **Proposed** | Decision is drafted but not yet accepted |
| **Accepted** | Decision is active and in effect |
| **Superseded** | Replaced by a newer ADR (link to the replacement) |
| **Deprecated** | No longer relevant; the thing it governed no longer exists |

When a decision changes, you do not edit the original ADR. You write a new ADR that supersedes it. The original remains as a historical record of what was decided and why -- future readers can trace the evolution of thinking.

### Good Pattern: Superseding an ADR

```markdown
# ADR-0011: Migrate from Self-Hosted Runners to Managed CI/CD

**Status:** Accepted
**Date:** 2026-02-20
**Supersedes:** ADR-0003

## Context
ADR-0003 chose self-hosted CI/CD runners for cost reasons. After 6 months,
the maintenance burden (patching, scaling, spot interruption handling) exceeds
the cost savings. Managed runner costs have decreased 40% since the original
decision.

## Decision
Migrate all CI/CD pipelines to managed runners. Decommission the self-hosted
runner infrastructure within 30 days.

## Consequences
- Monthly CI/CD cost increases ~$200/month
- Eliminates 4 hours/week of runner maintenance
- Removes the self-hosted runner Terraform module from the codebase
- ADR-0003 is now superseded
```

### Bad Pattern: Editing an Existing ADR

```markdown
# ADR-0003: Use Self-Hosted CI/CD Runners

**Status:** Accepted  ← WRONG: should be "Superseded by ADR-0011"
**Date:** 2025-08-10
**Updated:** 2026-02-20  ← WRONG: ADRs are immutable

## Decision
Use self-hosted runners. UPDATE: Actually, we switched to managed runners
on 2026-02-20 because maintenance was too high.
← WRONG: Write a new ADR instead of editing this one
```

Editing ADRs destroys the decision history. Six months from now, someone will ask "why did we originally choose self-hosted runners?" and the answer will be gone.

## What Gets an ADR

Not every decision needs an ADR. A good heuristic: if the decision would take more than 10 minutes to explain to a new team member, it deserves an ADR. If reverting the decision would take more than a day, it definitely deserves an ADR.

### Decisions That Deserve ADRs

| Category | Example Decisions |
|----------|-------------------|
| **Cloud foundation** | Cloud provider selection, account structure, region selection |
| **Architecture** | Container orchestration choice, database engine selection, API gateway |
| **Naming & governance** | Naming convention, tagging strategy, cost center taxonomy |
| **Security** | Identity provider, secrets management approach, encryption strategy |
| **Networking** | VPC design, DNS architecture, internal vs. external routing |
| **CI/CD** | Pipeline tool, deployment strategy, branch/tag conventions |
| **Data** | OLTP vs. OLAP separation, data warehouse selection, ETL tool |
| **Exemptions** | Anything managed via console instead of IaC (and why) |

### Decisions That Do Not Need ADRs

- Library version upgrades (unless they involve a major migration)
- Bug fixes
- Configuration changes within an established pattern
- Routine infrastructure scaling (adding replicas, increasing instance size)

## The First Three ADRs

Every infrastructure project should start with three ADRs before any resources exist:

```
ADR-0001: Adopt Architecture Decision Records
  Decision: Use ADRs for all significant infrastructure decisions.
  Format: Context → Decision → Consequences. Numbered, immutable, in version control.

ADR-0002: Naming Convention and Labels Module
  Decision: All resources follow <team>-<env>[-scope]-<name> pattern.
  A labels module is the first Terraform module. Invalid names rejected at plan time.

ADR-0003: Multi-Account Strategy
  Decision: Minimum six accounts -- management, security, log-archive, sandbox, dev, prod.
  Landing zone automation for governance. No application workloads in root account.
```

These three ADRs establish the governance foundation. Everything that follows references them. New team members read these three documents and understand the structural decisions before touching any code.

## Documenting Exemptions

Not everything can be managed in code. Some cloud services have immature Terraform provider support. Some configurations require console access. Some decisions are intentionally deferred. Every exemption from the "everything in code" principle gets documented in an ADR.

### Good Pattern: Explicit Exemption ADR

```markdown
# ADR-0009: Landing Zone Managed via Console, Not Terraform

**Status:** Accepted
**Date:** 2026-01-15

## Context
The Terraform provider for the cloud landing zone service does not support
account provisioning or guardrail management reliably. Applying Terraform
to landing zone resources has caused drift and required manual intervention
on three occasions.

## Decision
Manage the landing zone (account factory, guardrails, OU structure) via the
cloud console and CLI. Do NOT manage these resources in Terraform.

## Consequences
- Landing zone configuration is not version-controlled (accepted risk)
- Account provisioning is a manual process documented in the runbook
- This decision will be revisited when provider support matures
- All OTHER infrastructure remains in Terraform -- this exemption is narrow
```

Without this ADR, a well-intentioned engineer will try to move the landing zone into Terraform, hit the same problems, and waste a week rediscovering why it was managed via console in the first place.

## Where to Store ADRs

ADRs live in version control, alongside the code they govern. Two common patterns:

### Pattern 1: Dedicated Directory in the Infrastructure Repo

```
infrastructure/
├── adrs/
│   ├── ADR-0001-adopt-adrs.md
│   ├── ADR-0002-naming-convention.md
│   ├── ADR-0003-multi-account-strategy.md
│   └── ADR-0009-landing-zone-exemption.md
├── modules/
├── environments/
└── ...
```

### Pattern 2: ADRs in a Dedicated Repository

```
architecture-decisions/
├── ADR-0001-adopt-adrs.md
├── ADR-0002-naming-convention.md
├── ...
└── README.md   (index of all ADRs with status)
```

Pattern 1 is preferred for small teams with a single repository. Pattern 2 is better when ADRs span multiple repositories (e.g., infrastructure decisions that affect application code). In practice, a mature project accumulates 50-150 ADRs -- these should be stored centrally in one location, not scattered across service repositories. A dedicated `architecture-decisions` repo or a top-level `adrs/` directory in the root infrastructure repo keeps the full decision history searchable and browsable.

Regardless of where they live, ADRs must be:
- **Version-controlled** -- every change is tracked in git history
- **Discoverable** -- a README or index file lists all ADRs with their status
- **Reviewable** -- new ADRs go through the same pull request process as code

## ADR Index

Maintain a simple index file that lists every ADR with its number, title, and status. This is the entry point for new team members and the reference for existing ones.

```markdown
# Architecture Decision Records

| # | Title | Status | Date |
|---|-------|--------|------|
| ADR-0001 | Adopt Architecture Decision Records | Accepted | 2026-01-10 |
| ADR-0002 | Naming Convention and Labels Module | Accepted | 2026-01-10 |
| ADR-0003 | Multi-Account Strategy | Accepted | 2026-01-12 |
| ADR-0004 | Choose Container Orchestration | Accepted | 2026-01-15 |
| ADR-0005 | Organization Unit Structure | Accepted | 2026-01-15 |
| ADR-0009 | Landing Zone Console Exemption | Accepted | 2026-01-15 |
| ADR-0011 | Migrate to Managed CI/CD Runners | Accepted | 2026-02-20 |
```

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Where ADRs reference | Control Tower, SCPs, IAM Identity Center | Organization Policies, Cloud Identity | Management Groups, Microsoft Entra ID, Azure Policy |
| Console exemptions to document | Control Tower setup, some Security Hub standards | Organization setup, some Security Command Center configs | Landing Zone accelerator, some Defender configs |
| IaC provider maturity gaps | CT accounts, Inspector, some Config rules | Some Organization Policy types | Some Azure Policy definitions |
| Typical first ADR subjects | AWS vs. GCP vs. Azure, region, account structure | Project structure, region, VPC design | Subscription structure, region, landing zone |

ADRs are inherently cloud-agnostic. The format does not change. Only the decisions documented inside them reference cloud-specific services.

## Examples

Working implementations in `examples/`:
- **`examples/adr-template.md`** -- Ready-to-use ADR template with all three sections, status field, and instructions for superseding
- **`examples/first-three-adrs.md`** -- The three foundational ADRs every infrastructure project should start with: adopt ADRs, naming convention, and multi-account strategy

## Review Checklist

When reviewing infrastructure decisions and documentation:

- [ ] Every significant infrastructure decision has a corresponding ADR
- [ ] ADRs follow the standard format: Context, Decision, Consequences
- [ ] ADRs are numbered sequentially and numbers are never reused
- [ ] Superseded ADRs link to their replacement; original content is not edited
- [ ] An ADR index exists listing all ADRs with their current status
- [ ] ADRs are stored in version control and go through pull request review
- [ ] All ADRs are stored in a single central location, not scattered across service repos
- [ ] Console-managed resources have an exemption ADR documenting why they are not in code
- [ ] The first three ADRs (adopt ADRs, naming, account structure) exist before any resources
- [ ] New team members are directed to the ADR index as part of onboarding
- [ ] ADRs are concise (one page maximum) with no approval workflow overhead
- [ ] No ADR has been edited in place -- changes result in new ADRs with superseding links
- [ ] Exemption ADRs include a plan to revisit when the underlying limitation is resolved
