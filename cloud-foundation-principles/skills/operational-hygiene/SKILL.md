---
name: operational-hygiene
description: "This skill should be used when the user is addressing cloud resource sprawl, implementing cost attribution and tagging enforcement, setting up monitoring and alerting defaults, configuring drift detection for Terraform, designing lifecycle policies for storage and artifacts, or cleaning up after migrations. Covers resource cleanup discipline, cost center enforcement, monitoring with sensible defaults, scheduled drift detection, and lifecycle automation."
version: 1.0.0
---

# The Only Force That Defeats Cloud Entropy Is Enforced Discipline

Cloud infrastructure degrades through entropy. Every manual change, every forgotten resource, every untagged instance, every disabled alarm that was never re-enabled -- these are small acts of disorder that compound into large, expensive, ungovernable messes. Nobody wakes up one morning with a $40,000 surprise bill. They get there through twelve months of "we'll clean that up later."

Operational hygiene is not a project. It is a daily practice. It is the cloud infrastructure equivalent of washing dishes after every meal instead of letting them pile up for a week. The five pillars -- clean as you go, cost attribution, monitoring, drift detection, and lifecycle policies -- form a system where each reinforces the others.

## Pillar 1: Clean As You Go

The most expensive cloud resources are the ones nobody remembers creating. After every migration, every experiment, every proof-of-concept, clean up immediately. Not next sprint. Not after the launch. Now.

### The Rule

**If a resource has served its purpose, delete it in the same week.** Temporary resources that survive longer than one sprint become permanent. Permanent resources that nobody owns become liabilities.

### Good vs. Bad Patterns

**Bad: "We'll clean up after the migration"**
```
Week 1:  Migrate service-A from old cluster to new cluster
Week 4:  Migrate service-B
Week 8:  Migrate service-C
Week 12: "We should clean up the old cluster"
Week 20: Old cluster is still running, costing $2,400/month
Week 52: Nobody remembers what the old cluster does. Too risky to delete.
```

**Good: Clean up is part of the migration ticket**
```
Ticket: Migrate service-A to new cluster
  Subtask 1: Deploy service-A on new cluster
  Subtask 2: Reroute traffic to new cluster
  Subtask 3: Verify new deployment (48h monitoring)
  Subtask 4: Delete old service-A resources    <-- same ticket
  Subtask 5: Verify old resources are gone     <-- same ticket
```

### Common Cleanup Targets

| Resource Type | Typical Waste Pattern | Action |
|---------------|----------------------|--------|
| Old compute instances | Pre-migration servers still running | Terminate after migration verified |
| Unused load balancers | Created for testing, never deleted | Delete if no targets registered |
| Orphaned storage volumes | Detached from terminated instances | Snapshot (if needed) then delete |
| Stale DNS records | Point to decommissioned services | Remove or update |
| Unused security groups | Created per-service, service deleted | Delete if no attached resources |
| Old container images | Registry bloat from months of builds | Lifecycle policy (see Pillar 5) |
| Expired certificates | Renewed but old cert not cleaned up | Delete after renewal confirmed |
| Test/sandbox resources | "Temporary" resources from experiments | Weekly audit, auto-delete policy |

### The Don'ts List (Post to Your Team Channel)

- Do not create infrastructure in the cloud console. Console-created resources are invisible to Terraform and will be deleted when discovered.
- Do not give arbitrary names like `test-ec2-instance` or `temp-bucket-2`.
- Do not leave temporary resources running overnight without a documented expiration.
- Do not share one database across multiple services.
- Do not mix development and production data in the same environment.

## Pillar 2: Cost Attribution

Unattributable costs are uncontrollable costs. Every resource must have an owner and a cost center. This is not optional tagging -- it is enforced at the infrastructure-as-code layer.

### Required Tags on Every Resource

The canonical required tags list (`owner`, `environment`, `project`, `cost_center`, `iac_managed`) is defined in the `naming-and-labeling-as-code` skill. The labels module produces them automatically — engineers never type them manually.

### Enforcement in Code

Cost centers are validated at `terraform plan` time using a closed list defined in the labels module. The canonical cost center list and the pattern for defining company-specific domains live in the `naming-and-labeling-as-code` skill. Freeform tags are rejected before any resource is created -- a developer cannot accidentally create resources with `cost_center = "test"` or `cost_center = "misc"`. The labels module rejects it before anything is provisioned.

### Cost Review Cadence

| Frequency | Action |
|-----------|--------|
| Weekly | Review cost anomaly alerts (>20% increase from baseline) |
| Monthly | Review cost by cost center and team, identify top 5 cost drivers |
| Quarterly | Full cost optimization review: right-sizing, reserved instances, unused resources |

## Pillar 3: Monitoring with Sensible Defaults

Every service gets monitoring from the moment it is deployed. Not after the first incident. Not after someone asks "do we have alerting?" The monitoring module provides sensible defaults that work out of the box, with the ability to override thresholds per-service.

### Default Thresholds

| Metric | Default Threshold | Rationale |
|--------|-------------------|-----------|
| CPU utilization | 80% | Leaves headroom for traffic spikes |
| Memory utilization | 85% | OOM kills are catastrophic; catch early |
| Disk/storage free | 10GB or 10% | Disk-full crashes databases and logging |
| HTTP 5xx error rate | > 1% of requests | Backend errors visible to users |
| Response latency (p95) | Service-defined | Varies by service; must be explicitly set |
| Health check failures | 2 consecutive | Avoid alerting on transient network blips |
| Database connections | 80% of max | Connection exhaustion cascades to all clients |
| Read latency | 100ms | Slow reads indicate query or index issues |
| Write latency | 1s | Slow writes indicate lock contention or disk issues |

### The Disable Pattern

Not every alert makes sense for every service. Use a threshold sentinel value of `-1` to disable specific alarms without removing the monitoring module.

```hcl
module "alerts" {
  source = "git::https://github.com/myorg/tf-module-alerts.git?ref=v1.3.0"

  service_name = "myapp-api"
  alarm_email  = "myapp-team@myorg.com"

  # Use defaults for most thresholds
  cpu_utilization_threshold = 80    # default
  storage_free_threshold    = 10    # default (GB)

  # Disable network alerting (not relevant for this service)
  network_in_threshold  = -1
  network_out_threshold = -1

  # Custom threshold for this specific service
  http_5xx_threshold = 0.5  # Stricter than default: alert at 0.5% error rate
}
```

Inside the module, the `-1` sentinel disables alarm creation:

```hcl
locals {
  create_cpu_alarm     = var.cpu_utilization_threshold >= 0
  create_network_alarm = var.network_in_threshold >= 0
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = local.create_cpu_alarm ? 1 : 0
  # ... alarm configuration
}
```

### Missing Data Handling

Configure alarms to treat missing data as "not breaching." Services that scale to zero (serverless, spot instances) should not trigger alarms when no data is reported. This prevents alarm storms during expected idle periods.

## Pillar 4: Drift Detection

Infrastructure drift occurs when someone modifies a resource outside of Terraform -- through the cloud console, a CLI command, or another automation tool. Drift is silent, invisible, and dangerous. The infrastructure your code describes and the infrastructure that actually exists diverge without anyone knowing.

### Scheduled Plan Detection

Run `terraform plan` on a schedule (daily for production, weekly for development). Any planned changes on a clean state indicate drift -- someone changed something outside of Terraform. The `terraform plan -detailed-exitcode` flag is critical: exit code 0 means no changes (clean), exit code 2 means drift detected. Alert on exit code 2.

For a complete drift detection pipeline implementation (GitHub Actions workflow with matrix strategy across layers, alerting, and scheduling), see the `unified-cicd-platform` skill.

### What Drift Indicates

| Drift Type | Cause | Action |
|------------|-------|--------|
| Security group rule added | Console change during incident | Import into Terraform or revert |
| Instance type changed | Manual right-sizing | Update Terraform to match or revert |
| Tag missing | Resource modified outside IaC | Re-apply Terraform to restore tags |
| Resource deleted | Manual cleanup without IaC update | Remove from Terraform state or recreate |
| New resource exists | Console-created, not in Terraform | Import into Terraform or delete |

### The Policy

**Infrastructure not in code is a liability.** Console-created resources will be deleted when discovered. If an emergency required a console change, the change must be imported into Terraform within 48 hours and documented in an ADR or incident report.

## Pillar 5: Lifecycle Policies

Storage, logs, artifacts, and snapshots accumulate silently. Without lifecycle policies, a $5/month logging bill becomes a $500/month logging bill within a year.

### Storage Tiering

```hcl
# S3 lifecycle policy for data ingestion buckets
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"    # Infrequent access after 30 days
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"     # Archive after 90 days
    }

    expiration {
      days = 365                        # Delete after 1 year
    }
  }
}
```

### Log Retention

```hcl
# Log group with explicit retention
resource "aws_cloudwatch_log_group" "service" {
  name              = "/ecs/${module.labels.prefix}myapp-api"
  retention_in_days = 90    # Production logs: 90 days

  # Dev logs: 14 days is sufficient
  # retention_in_days = 14
}
```

Never create log groups without a retention policy. The default in most cloud providers is "retain forever," which means unbounded cost growth.

### Artifact Cleanup

| Artifact Type | Retention Policy | Rationale |
|---------------|-----------------|-----------|
| Container images | See `container-image-tagging` skill | Retention policy defined with full Terraform example |
| Database snapshots | 14 days automated, manual snapshots reviewed monthly | Compliance + cost control |
| Build artifacts | 30 days | Rarely needed after deployment verified |
| Terraform plan files | 7 days | Only needed during review cycle |
| Temporary uploads | 24 hours | Processing should be complete; auto-expire |

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Cost attribution | Cost Explorer + Cost Categories | Billing Reports + Labels | Cost Management + Tags |
| Cost anomaly detection | Cost Anomaly Detection | Budget Alerts | Cost Alerts |
| Monitoring alarms | CloudWatch Alarms | Cloud Monitoring Alerting Policies | Azure Monitor Alerts |
| Log retention | CloudWatch Logs retention_in_days | Cloud Logging retention settings | Log Analytics retention |
| Storage lifecycle | S3 Lifecycle Configuration | GCS Lifecycle Rules | Blob Lifecycle Management |
| Drift detection | `terraform plan -detailed-exitcode` | `terraform plan -detailed-exitcode` | `terraform plan -detailed-exitcode` |
| Compliance scanning | AWS Config Rules | Organization Policy Constraints | Azure Policy |
| Resource inventory | AWS Config Recorder | Cloud Asset Inventory | Azure Resource Graph |

## Examples

Working implementations in `examples/`:
- **`examples/monitoring-and-alerting-module.md`** -- Terraform monitoring module with sensible defaults, the `-1` disable pattern, and missing-data-safe alarm configurations across compute, database, and HTTP services
- **`examples/drift-detection-pipeline.md`** -- Scheduled CI/CD pipeline that runs `terraform plan` daily, detects drift via exit codes, and alerts the team with actionable context

## Review Checklist

When designing or reviewing operational hygiene practices:

- [ ] Resource cleanup is a subtask of every migration, experiment, and proof-of-concept ticket
- [ ] No temporary resources survive longer than one sprint without a documented expiration
- [ ] Every resource carries the required tags (see `naming-and-labeling-as-code` skill for the canonical list)
- [ ] Cost centers are validated at `terraform plan` time via a closed list in the labels module
- [ ] Cost anomaly alerts are configured (>20% increase from baseline triggers notification)
- [ ] Every service has monitoring from day one with sensible default thresholds
- [ ] Alert thresholds can be overridden per-service; individual alarms can be disabled via `-1` sentinel
- [ ] Missing data is treated as "not breaching" to prevent alarm storms during expected idle periods
- [ ] Scheduled `terraform plan` runs detect drift daily in production, weekly in development
- [ ] Console-created resources are imported into Terraform within 48 hours or deleted
- [ ] Storage lifecycle policies are set on every bucket, log group, and artifact repository
- [ ] Container registry lifecycle policies are configured (see `container-image-tagging` skill for retention rules)
- [ ] Log groups have explicit retention periods (never "retain forever")
- [ ] Monthly cost reviews identify top cost drivers and unattributed spend
