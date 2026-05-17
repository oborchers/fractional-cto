---
name: operational-hygiene
description: "Use when cleaning up unused cloud resources after migrations, enforcing cost attribution tags on AWS/GCP/Azure infrastructure, configuring default CloudWatch or Cloud Monitoring alerting thresholds, running scheduled Terraform drift detection pipelines, setting up S3 lifecycle rules or GCS lifecycle policies, auditing cloud billing for unattributed spend, or automating artifact retention for container registries and log groups. Covers resource cleanup automation, cost center tag enforcement at terraform plan time, monitoring module defaults with per-service overrides, scheduled drift detection via terraform plan -detailed-exitcode, and storage/log/artifact lifecycle policy configuration."
version: 1.0.0
---

# Operational Hygiene

Enforce five pillars of cloud infrastructure discipline: resource cleanup, cost attribution, monitoring defaults, drift detection, and lifecycle policies. Each pillar has concrete enforcement mechanisms — not just guidelines.

## Pillar 1: Resource Cleanup

**Rule:** Delete temporary resources in the same sprint they were created. Include cleanup as a subtask in every migration, experiment, and proof-of-concept ticket.

**Cleanup targets:**

| Resource Type | Action |
|---------------|--------|
| Old compute instances | Terminate after migration verified |
| Unused load balancers | Delete if no targets registered |
| Orphaned storage volumes | Snapshot if needed, then delete |
| Stale DNS records | Remove or update |
| Unused security groups | Delete if no attached resources |
| Old container images | Apply lifecycle policy (see Pillar 5) |
| Test/sandbox resources | Weekly audit, auto-delete policy |

**Verification:** Run `aws ec2 describe-instances --filters "Name=tag:environment,Values=sandbox" --query 'Reservations[].Instances[?LaunchTime<=\`2024-01-01\`]'` (or equivalent) to find stale resources.

**Rules:**
- Never create infrastructure in the cloud console — console-created resources are invisible to Terraform
- Never leave temporary resources running without a documented expiration
- Never share one database across multiple services

## Pillar 2: Cost Attribution

Every resource must have an owner and cost center, enforced at the infrastructure-as-code layer.

Required tags (`owner`, `environment`, `project`, `cost_center`, `iac_managed`) are defined in the `naming-and-labeling-as-code` skill. The labels module produces them automatically and validates cost centers at `terraform plan` time against a closed list — freeform values like `cost_center = "test"` are rejected before provisioning.

**Cost review cadence:**

| Frequency | Action |
|-----------|--------|
| Weekly | Review cost anomaly alerts (>20% increase from baseline) |
| Monthly | Review cost by cost center, identify top 5 drivers |
| Quarterly | Right-sizing, reserved instances, unused resource audit |

**Verification:** `aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-02-01 --granularity MONTHLY --group-by Type=TAG,Key=cost_center` to confirm attribution coverage.

## Pillar 3: Monitoring Defaults

Every service gets monitoring at deployment. The monitoring module provides defaults with per-service overrides.

**Default thresholds:**

| Metric | Threshold |
|--------|-----------|
| CPU utilization | 80% |
| Memory utilization | 85% |
| Disk/storage free | 10GB or 10% |
| HTTP 5xx error rate | > 1% of requests |
| Response latency (p95) | Service-defined (required) |
| Health check failures | 2 consecutive |
| Database connections | 80% of max |

**Disable pattern:** Use `-1` sentinel to disable specific alarms without removing the module:

```hcl
module "alerts" {
  source = "git::https://github.com/myorg/tf-module-alerts.git?ref=v1.3.0"

  service_name = "myapp-api"
  alarm_email  = "myapp-team@myorg.com"

  network_in_threshold  = -1  # Disable — not relevant for this service
  http_5xx_threshold    = 0.5 # Stricter than default
}
```

Configure missing data as "not breaching" for services that scale to zero.

## Pillar 4: Drift Detection

Run `terraform plan -detailed-exitcode` on schedule (daily for production, weekly for dev). Exit code 2 = drift detected — alert the team.

For the full pipeline implementation (GitHub Actions workflow with matrix strategy), see the `unified-cicd-platform` skill.

**Drift response:**

| Drift Type | Action |
|------------|--------|
| Security group rule added | Import into Terraform or revert |
| Instance type changed | Update Terraform to match or revert |
| Tag missing | Re-apply Terraform to restore tags |
| Resource deleted outside IaC | Remove from state or recreate |
| Console-created resource | Import within 48h or delete |

**Policy:** Console-created resources are deleted when discovered. Emergency console changes must be imported into Terraform within 48 hours and documented in an ADR.

## Pillar 5: Lifecycle Policies

**Storage tiering:**

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    transition { days = 30;  storage_class = "STANDARD_IA" }
    transition { days = 90;  storage_class = "GLACIER_IR" }
    expiration { days = 365 }
  }
}
```

**Log retention** — always set explicitly (never "retain forever"):

```hcl
resource "aws_cloudwatch_log_group" "service" {
  name              = "/ecs/${module.labels.prefix}myapp-api"
  retention_in_days = 90  # Production: 90 days, Dev: 14 days
}
```

**Artifact retention:**

| Artifact Type | Retention |
|---------------|-----------|
| Container images | See `container-image-tagging` skill |
| Database snapshots | 14 days automated, manual reviewed monthly |
| Build artifacts | 30 days |
| Terraform plan files | 7 days |
| Temporary uploads | 24 hours |

**Verification:** `aws s3api get-bucket-lifecycle-configuration --bucket my-bucket` to confirm policies are active.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Cost attribution | Cost Explorer + Cost Categories | Billing Reports + Labels | Cost Management + Tags |
| Monitoring alarms | CloudWatch Alarms | Cloud Monitoring Alerting Policies | Azure Monitor Alerts |
| Log retention | CloudWatch Logs retention_in_days | Cloud Logging retention settings | Log Analytics retention |
| Storage lifecycle | S3 Lifecycle Configuration | GCS Lifecycle Rules | Blob Lifecycle Management |
| Drift detection | `terraform plan -detailed-exitcode` | Same | Same |
| Resource inventory | AWS Config Recorder | Cloud Asset Inventory | Azure Resource Graph |

## Examples

Working implementations in `examples/`:
- **`examples/monitoring-and-alerting-module.md`** — Terraform monitoring module with defaults, `-1` disable pattern, and missing-data-safe alarms
- **`examples/drift-detection-pipeline.md`** — Scheduled CI/CD pipeline with drift detection, exit code alerting, and actionable context

## Review Checklist

- [ ] Resource cleanup is a subtask of every migration and experiment ticket
- [ ] No temporary resources survive longer than one sprint without documented expiration
- [ ] Every resource carries required tags (see `naming-and-labeling-as-code` skill)
- [ ] Cost centers validated at `terraform plan` time via closed list
- [ ] Cost anomaly alerts configured (>20% increase triggers notification)
- [ ] Every service has monitoring from day one with default thresholds
- [ ] Alert thresholds overridable per-service; `-1` sentinel disables individual alarms
- [ ] Missing data treated as "not breaching" for scale-to-zero services
- [ ] Scheduled `terraform plan` detects drift daily (production), weekly (dev)
- [ ] Console-created resources imported into Terraform within 48h or deleted
- [ ] Storage lifecycle policies set on every bucket, log group, and artifact repository
- [ ] Container registry lifecycle configured (see `container-image-tagging` skill)
- [ ] Log groups have explicit retention (never "retain forever")
- [ ] Monthly cost reviews identify top drivers and unattributed spend
