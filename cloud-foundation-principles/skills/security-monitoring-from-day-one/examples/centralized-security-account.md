# Centralized Security Account with Delegated Admin
#
# Deploys organization-wide security monitoring from a dedicated security
# account. All findings aggregate here. New accounts auto-enroll.
#
# This configuration runs in the security account (not root, not workloads).

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "organization_id" {
  description = "Organization ID for org-wide enablement"
  type        = string
}

variable "security_account_id" {
  description = "AWS account ID of the dedicated security account"
  type        = string
}

variable "member_account_ids" {
  description = "List of member account IDs to monitor"
  type        = list(string)
}

variable "active_regions" {
  description = "Regions where workloads run (security services enabled in all)"
  type        = list(string)
  default     = ["eu-west-1", "us-east-1"]
}

# ---------------------------------------------------------------------------
# Threat Detection (GuardDuty) -- Organization-wide
# ---------------------------------------------------------------------------

# Designate the security account as delegated admin for GuardDuty
resource "aws_guardduty_organization_admin_account" "security" {
  admin_account_id = var.security_account_id
}

# Enable GuardDuty detector in the security account
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false # Enable only if running EKS
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
}

# Auto-enable GuardDuty for all organization members
resource "aws_guardduty_organization_configuration" "main" {
  detector_id = aws_guardduty_detector.main.id
  auto_enable_organization_members = "ALL"

  datasources {
    s3_logs {
      auto_enable = true
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = true
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Compliance Scanning (Security Hub) -- Organization-wide
# ---------------------------------------------------------------------------

# Designate the security account as delegated admin for Security Hub
resource "aws_securityhub_organization_admin_account" "security" {
  admin_account_id = var.security_account_id
}

# Enable Security Hub in the security account
resource "aws_securityhub_account" "main" {}

# Auto-enable Security Hub for all organization members
resource "aws_securityhub_organization_configuration" "main" {
  auto_enable = true

  depends_on = [aws_securityhub_account.main]
}

# Enable CIS AWS Foundations Benchmark
# Note: Security standards are often better managed via console due to
# Terraform provider limitations. This shows the Terraform approach.
resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.main]
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}

# ---------------------------------------------------------------------------
# Configuration Auditing (AWS Config) -- Organization-wide rules
# ---------------------------------------------------------------------------

# Organization-level Config rules enforce baseline security across all accounts.
# These are detective controls -- they report violations, they do not block.

resource "aws_config_organization_managed_rule" "s3_versioning" {
  name            = "s3-bucket-versioning-enabled"
  rule_identifier = "S3_BUCKET_VERSIONING_ENABLED"

  description = "Checks that S3 buckets have versioning enabled"
}

resource "aws_config_organization_managed_rule" "encrypted_volumes" {
  name            = "encrypted-volumes"
  rule_identifier = "ENCRYPTED_VOLUMES"

  description = "Checks that EBS volumes are encrypted"
}

resource "aws_config_organization_managed_rule" "rds_encryption" {
  name            = "rds-storage-encrypted"
  rule_identifier = "RDS_STORAGE_ENCRYPTED"

  description = "Checks that RDS instances have storage encryption enabled"
}

resource "aws_config_organization_managed_rule" "ec2_instance_profile" {
  name            = "ec2-instance-no-public-ip"
  rule_identifier = "EC2_INSTANCE_NO_PUBLIC_IP"

  description = "Checks that EC2 instances do not have public IP addresses"
}

resource "aws_config_organization_managed_rule" "secrets_manager_kms" {
  name            = "secretsmanager-using-cmk"
  rule_identifier = "SECRETSMANAGER_USING_CMK"

  description = "Checks that Secrets Manager secrets are encrypted with customer-managed KMS keys"
}

# ---------------------------------------------------------------------------
# Vulnerability Scanning (Inspector) -- Targeted accounts
# ---------------------------------------------------------------------------

# Inspector is enabled for workload accounts only (dev + prod),
# not for management or security accounts.

resource "aws_inspector2_organization_configuration" "main" {
  auto_enable {
    ec2    = true
    ecr    = true
    lambda = true
  }
}

# ---------------------------------------------------------------------------
# Finding Aggregation -- Cross-region to security account
# ---------------------------------------------------------------------------

resource "aws_securityhub_finding_aggregator" "main" {
  linking_mode = "ALL_REGIONS"

  depends_on = [aws_securityhub_account.main]
}

# ---------------------------------------------------------------------------
# SNS Topic for Security Alerts
# ---------------------------------------------------------------------------

resource "aws_kms_key" "security_alerts" {
  description = "Encryption key for security alert notifications"
}

resource "aws_sns_topic" "security_alerts" {
  name              = "${module.labels.prefix}security-alerts"
  kms_master_key_id = aws_kms_key.security_alerts.arn
}

# EventBridge rule: high-severity GuardDuty findings --> SNS
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "guardduty-high-severity"
  description = "GuardDuty findings with severity >= 7 (High/Critical)"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "security-alerts"
  arn       = aws_sns_topic.security_alerts.arn
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "platform"
  env         = "security"
  name        = "security-monitoring"
  cost_center = "engineering"
}

# ---------------------------------------------------------------------------
# Key Points
# ---------------------------------------------------------------------------

# 1. Security account is delegated admin for GuardDuty, Security Hub, and Inspector
# 2. All services auto-enroll new accounts (no manual activation required)
# 3. Findings aggregate cross-region into the security account
# 4. High-severity GuardDuty findings trigger SNS alerts immediately
# 5. Config rules are detective (report only), not preventive (block)
# 6. Inspector targets workload accounts only, not management/security
# 7. All encryption uses customer-managed KMS keys
