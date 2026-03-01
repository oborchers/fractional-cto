# Detective Controls Baseline
#
# Configuration audit rules deployed as detective controls across all
# accounts. Production gets additional workload-specific protections.
#
# Strategy:
#   - Detective controls: deploy everywhere immediately (zero risk)
#   - Preventive controls: test in dev 1+ week, then promote to prod
#   - Workload-specific: production only (avoids dev noise)

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "enable_workload_protections" {
  description = "Enable workload-specific protections (true for prod only)"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Labels
# ---------------------------------------------------------------------------

module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "platform"
  env         = var.environment
  name        = "security-baseline"
  cost_center = "engineering"
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  is_prod = var.environment == "prod"

  # Core detective rules: enabled in ALL environments
  core_detective_rules = {
    "s3-bucket-public-read-prohibited" = {
      identifier  = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
      description = "S3 buckets must not allow public read access"
    }
    "s3-bucket-ssl-requests-only" = {
      identifier  = "S3_BUCKET_SSL_REQUESTS_ONLY"
      description = "S3 buckets must require SSL for requests"
    }
    "rds-storage-encrypted" = {
      identifier  = "RDS_STORAGE_ENCRYPTED"
      description = "RDS instances must have encrypted storage"
    }
    "encrypted-volumes" = {
      identifier  = "ENCRYPTED_VOLUMES"
      description = "EBS volumes must be encrypted"
    }
    "restricted-ssh" = {
      identifier  = "INCOMING_SSH_DISABLED"
      description = "Security groups must not allow unrestricted SSH (0.0.0.0/0:22)"
    }
    "iam-root-access-key-check" = {
      identifier  = "IAM_ROOT_ACCESS_KEY_CHECK"
      description = "Root account must not have access keys"
    }
    "cloud-trail-enabled" = {
      identifier  = "CLOUD_TRAIL_ENABLED"
      description = "CloudTrail must be enabled in the account"
    }
    "rds-instance-public-access-check" = {
      identifier  = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
      description = "RDS instances must not be publicly accessible"
    }
  }

  # Production-only detective rules: more detailed, potentially noisier
  prod_detective_rules = {
    "rds-multi-az-support" = {
      identifier  = "RDS_MULTI_AZ_SUPPORT"
      description = "Production RDS instances must be Multi-AZ"
    }
    "s3-bucket-versioning-enabled" = {
      identifier  = "S3_BUCKET_VERSIONING_ENABLED"
      description = "Production S3 buckets must have versioning enabled"
    }
    "ecs-task-definition-log-configuration" = {
      identifier  = "ECS_TASK_DEFINITION_LOG_CONFIGURATION"
      description = "ECS task definitions must have log configuration"
    }
    "alb-waf-enabled" = {
      identifier  = "ALB_WAF_ENABLED"
      description = "Production ALBs must have WAF enabled"
    }
  }

  # Merge: all environments get core, prod also gets prod-specific
  active_rules = local.is_prod ? merge(local.core_detective_rules, local.prod_detective_rules) : local.core_detective_rules
}

# ---------------------------------------------------------------------------
# AWS Config Recorder (prerequisite)
# ---------------------------------------------------------------------------

resource "aws_config_configuration_recorder" "main" {
  name     = "${module.labels.prefix}-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "${module.labels.prefix}-delivery"
  s3_bucket_name = aws_s3_bucket.config.id

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

# ---------------------------------------------------------------------------
# Detective Controls -- Config Rules (report only, never block)
# ---------------------------------------------------------------------------

resource "aws_config_config_rule" "detective" {
  for_each = local.active_rules

  name        = "${module.labels.prefix}-${each.key}"
  description = each.value.description

  source {
    owner             = "AWS"
    source_identifier = each.value.identifier
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# ---------------------------------------------------------------------------
# Workload-Specific Protections (production only)
# ---------------------------------------------------------------------------

# GuardDuty workload protections -- only in production
resource "aws_guardduty_detector_feature" "rds_login" {
  count = var.enable_workload_protections ? 1 : 0

  detector_id = data.aws_guardduty_detector.current.id
  name        = "RDS_LOGIN_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ecs_runtime" {
  count = var.enable_workload_protections ? 1 : 0

  detector_id = data.aws_guardduty_detector.current.id
  name        = "RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "ECS_FARGATE_AGENT_MANAGEMENT"
    status = "ENABLED"
  }
}

# ---------------------------------------------------------------------------
# Pre-commit Security Scanning (CI/CD complement)
# ---------------------------------------------------------------------------

# This Terraform file enforces runtime detective controls.
# CI/CD pipelines should also run pre-commit security scanning:
#
# .pre-commit-config.yaml:
#   repos:
#     - repo: https://github.com/antonbabenko/pre-commit-terraform
#       hooks:
#         - id: terraform_fmt        # Code formatting
#         - id: terraform_tflint     # Static analysis
#         - id: terraform_checkov    # Security policy scanning
#
# Checkov catches misconfigurations before they reach the cloud.
# Config Rules catch misconfigurations that slip through CI/CD.
# Both are needed -- defense in depth.

# ---------------------------------------------------------------------------
# S3 Bucket for Config delivery (required for Config to operate)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "config" {
  bucket = "${module.labels.prefix}-config-recordings"
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# IAM Role for Config Recorder
# ---------------------------------------------------------------------------

resource "aws_iam_role" "config" {
  name = "${module.labels.prefix}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "config.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3" {
  name = "${module.labels.prefix}-config-s3"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.config.arn}/*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl" = "bucket-owner-full-control"
        }
      }
    }, {
      Effect   = "Allow"
      Action   = ["s3:GetBucketAcl"]
      Resource = aws_s3_bucket.config.arn
    }]
  })
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_guardduty_detector" "current" {}

# ---------------------------------------------------------------------------
# Key Points
# ---------------------------------------------------------------------------

# 1. Core detective rules deploy to ALL environments (dev, staging, prod)
# 2. Production gets additional rules (Multi-AZ, WAF, versioning, logging)
# 3. All rules are DETECTIVE (report findings), not PREVENTIVE (block deploys)
# 4. Workload-specific GuardDuty protections (RDS, ECS runtime) are prod-only
# 5. Pre-commit scanning in CI/CD complements runtime Config rules
# 6. Config rule findings flow to Security Hub for central aggregation
# 7. To promote a detective control to preventive: create an SCP or Config
#    remediation action, test in dev for 2+ weeks, then enable in prod
