---
name: security-monitoring-from-day-one
description: "This skill should be used when the user is setting up security monitoring, enabling threat detection, configuring compliance scanning, deploying vulnerability scanners, creating a security account, centralizing security findings, choosing between detective and preventive controls, or deciding when to enable security services. Covers the four security pillars (threat detection, compliance scanning, vulnerability scanning, configuration auditing), centralized security accounts with delegated admin, detective-before-preventive strategy, and managed security services over custom SIEM."
version: 1.0.0
---

# Security Monitoring Deploys in Week 2, Not After the Breach

Security monitoring is not a feature you add when the compliance audit arrives. It ships alongside the infrastructure -- in week 2, right after account structure and networking. Every week without monitoring is a week where threats go undetected, misconfigurations accumulate silently, and vulnerabilities sit in production unscanned. The cost of enabling managed security services on day one is trivial. The cost of discovering six months of unmonitored exposure is catastrophic.

Start with managed security services. Do not build a custom SIEM. Do not cobble together open-source tools. Use the cloud provider's native threat detection, compliance scanning, and vulnerability assessment. These services integrate with each other, aggregate findings centrally, and require no infrastructure to operate. You can always add third-party tools later -- but you cannot retroactively detect last month's intrusion.

**Week 2 means enabling the managed services with default settings -- not tuning every rule.** Turn on threat detection and basic configuration auditing. The full compliance framework and workload-specific scanning comes later as you understand your baseline. The landing zone tooling (see `multi-account-from-day-one` skill) handles the account structure and guardrails; this skill covers the security services you enable on top of that foundation.

## The Four Security Pillars

Every cloud foundation needs four categories of security monitoring deployed from the start. Each pillar answers a different question.

| Pillar | Question It Answers | What It Detects |
|--------|---------------------|-----------------|
| **Threat Detection** | Is someone attacking us right now? | Unauthorized API calls, compromised credentials, cryptocurrency mining, port scanning, data exfiltration |
| **Compliance Scanning** | Do our resources meet security standards? | CIS benchmark violations, industry framework gaps, security best practice deviations |
| **Vulnerability Scanning** | Do our workloads have known weaknesses? | CVEs in container images, OS packages, application dependencies, network reachability issues |
| **Configuration Auditing** | Are resources configured safely? | Unencrypted storage, public access, missing logging, overly permissive IAM, security group misconfigurations |

All four pillars must be active. Threat detection without configuration auditing means you catch the attacker but not the open door they walked through. Vulnerability scanning without compliance means you patch CVEs but miss the S3 bucket that is publicly readable.

## Centralized Security Account with Delegated Admin

Security findings from every account and project must flow to a single, dedicated security account. This account is not the root/management account (which should have minimal services), and it is not a workload account (which teams modify daily). It is a purpose-built aggregation point.

**Architecture pattern:**

```
security-central (delegated admin)
  |-- Threat detection coordinator
  |-- Compliance aggregator
  |-- Vulnerability scanner admin
  |-- Configuration rule evaluator
  |
  +-- Findings flow from:
      |-- dev account
      |-- staging account
      |-- prod account
      |-- data account
      +-- any future accounts (auto-enrolled)
```

**Delegated admin, not super-admin.** The security account administers security services on behalf of the organization. It does not have root-level access to member accounts. It can view findings, manage security standards, and coordinate scanners -- but it cannot modify workloads, deploy applications, or change IAM policies in other accounts.

**Auto-enrollment for new accounts.** When a new account or project joins the organization, security services must activate automatically. Manual enrollment means gaps. Configure the security service at the organization level so every new member inherits monitoring from creation.

## Detective Controls First, Preventive Controls After Validation

This ordering is critical and frequently violated by teams that rush to "lock things down."

**Detective controls observe and report.** They tell you what is happening without blocking anything. Deploy them to production immediately. They have zero operational risk -- they cannot break deployments, block API calls, or cause outages.

**Preventive controls block and enforce.** They reject non-compliant configurations at deployment time. They can and will break deployments if misconfigured. A misconfigured preventive control in production at 2 AM is an outage, not security.

**The correct sequence:**

1. **Week 2:** Enable all detective controls in all environments. Let them run. Review findings.
2. **Weeks 3-4:** Triage findings. Separate real issues from noise. Tune thresholds.
3. **Week 5+:** Promote validated detective controls to preventive -- in dev first. Run for at least two weeks.
4. **After validation:** Enable preventive controls in production, one at a time.

**With only dev and prod environments** (the recommended starting point -- see `tag-based-production-deploys` skill), the validation window matters more. Run preventive controls in dev for at least two weeks before production. If a control blocks a legitimate pattern in dev, it will block it in prod. Pay close attention to any suppressions or exceptions needed during the dev validation period.

```
# Good: detective controls everywhere, preventive controls tested in dev first

Detective (all environments, immediate):
  - "S3 bucket is publicly accessible" --> finding, notification
  - "Security group allows 0.0.0.0/0 on port 22" --> finding, notification
  - "RDS instance is not encrypted" --> finding, notification

Preventive (dev first, then prod after 2+ weeks):
  - "Block creation of unencrypted S3 buckets" --> deployment rejected
  - "Block security groups with 0.0.0.0/0 on port 22" --> deployment rejected
```

```
# Bad: preventive controls in production without validation

Day 1: Enable "block all non-compliant resources" in production
Day 2: Production deployment fails because the rule doesn't account
        for a legitimate exception (e.g., a public-facing CDN origin bucket)
Day 2: Team disables ALL security controls to unblock the deployment
Day 3: Security controls remain disabled "temporarily" for six months
```

## Quarterly Review Cycle

Security monitoring is not set-and-forget. Schedule quarterly reviews to:

- **Review suppressed findings** -- are they still valid suppressions or stale?
- **Evaluate new security standards** -- has the provider released new compliance checks?
- **Audit coverage gaps** -- are new services or accounts enrolled in monitoring?
- **Tune detection thresholds** -- are alerts actionable or just noise?
- **Promote detective to preventive** -- which findings are stable enough to enforce?

Without quarterly reviews, security findings accumulate into an unmanageable backlog. Teams stop looking at the dashboard. Monitoring becomes expensive decoration.

## What to Enable and Where

Not every pillar needs the same coverage in every environment. Production gets full protection. Dev environments get baseline monitoring. This avoids alert fatigue from non-production noise.

| Capability | Dev | Staging | Prod |
|------------|-----|---------|------|
| Threat detection (base) | Yes | Yes | Yes |
| Threat detection (workload-specific) | No | No | Yes |
| Compliance scanning | Baseline | Baseline | Full |
| Vulnerability scanning (containers) | CI/CD only | CI/CD only | Runtime + CI/CD |
| Vulnerability scanning (hosts) | No | No | Yes |
| Configuration auditing | Core rules | Core rules | All rules |

**CI/CD scanning complements, never replaces, runtime scanning.** A container image scanned clean at build time can become vulnerable the next day when a new CVE is published. Runtime scanning catches what the build pipeline missed.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Threat detection | GuardDuty | SCC Premium Threat Detection | Microsoft Sentinel |
| Compliance scanning | Security Hub | Security Command Center | Defender for Cloud |
| Vulnerability scanning | Inspector | Container Analysis / Artifact Analysis | Defender for Containers |
| Configuration auditing | AWS Config Rules | Policy Analyzer + Asset Inventory | Azure Policy |
| Centralized security account | Delegated admin in security account | Organization-level SCC in security project | Defender for Cloud in management subscription |
| Finding aggregation | Security Hub (aggregates GuardDuty, Inspector, Config) | SCC (aggregates all findings) | Defender for Cloud (unified dashboard) |
| Auto-enrollment | Organization-wide enablement via delegated admin | Organization-level SCC activation | Management group policy assignment |

## Examples

Working implementations in `examples/`:
- **`examples/centralized-security-account.md`** -- Terraform configuration for a dedicated security account/project with delegated admin, organization-wide threat detection, compliance scanning, and finding aggregation
- **`examples/detective-controls-baseline.md`** -- Baseline configuration audit rules deployed across all accounts with selective workload-specific protections for production only

## Review Checklist

When designing or reviewing security monitoring:

- [ ] A dedicated security account/project exists, separate from root and workload accounts
- [ ] Threat detection is enabled organization-wide with auto-enrollment for new accounts
- [ ] Compliance scanning runs against at least CIS benchmarks in all production accounts
- [ ] Vulnerability scanning covers container images in both CI/CD pipelines and runtime
- [ ] Configuration audit rules are deployed as detective controls first, not preventive
- [ ] Preventive controls are validated in dev for at least two weeks before production
- [ ] All findings aggregate to a central dashboard in the security account
- [ ] Workload-specific protections (database, container runtime, storage) are enabled in production
- [ ] A quarterly review process exists for finding triage, threshold tuning, and coverage gaps
- [ ] Security monitoring was deployed in the first two weeks, not deferred to "later"
- [ ] Managed security services are used -- no self-hosted SIEM or custom detection pipelines
- [ ] CI/CD pipelines include pre-commit security scanning (static analysis, policy checks)
