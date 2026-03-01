# Secrets and Configuration Separation
#
# Everything the service needs at runtime goes into ONE Secrets Manager secret
# as a JSON blob. No SSM Parameter Store for app config. No individual secrets
# per key. One path: /{service}/env -- same in every account.
#
# Account = environment (multi-account strategy). The secret path is identical
# in dev and prod. Application code never knows which environment it runs in.
#
# Infrastructure-to-infrastructure wiring (VPC IDs, subnet IDs, database
# endpoints that change when infra changes) flows through Terraform outputs
# or SSM Parameter Store -- not the service secret.

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "service_name" {
  description = "Service identifier for naming"
  type        = string
  default     = "myapp"
}

variable "image_tag" {
  description = "Container image tag (git SHA or semantic version, never 'latest')"
  type        = string
}

variable "db_instance_address" {
  description = "Database endpoint (from network/database layer via remote state)"
  type        = string
}

variable "db_instance_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "redis_endpoint" {
  description = "Redis endpoint (from cache layer via remote state)"
  type        = string
}

# ---------------------------------------------------------------------------
# KMS Key -- Customer-Managed Encryption
# ---------------------------------------------------------------------------

resource "aws_kms_key" "secrets" {
  description         = "Encryption key for ${var.service_name} secrets"
  enable_key_rotation = true

  tags = local.tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.service_name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ---------------------------------------------------------------------------
# The One Secret -- /{service}/env
# ---------------------------------------------------------------------------

# Single JSON blob containing EVERY env var the service needs.
# Credentials and configuration together. One path. One IAM policy.

resource "aws_secretsmanager_secret" "env" {
  name       = "/${var.service_name}/env"
  kms_key_id = aws_kms_key.secrets.arn

  description = "All environment variables for ${var.service_name}"

  tags = local.tags
}

# Initial secret value -- Terraform creates it, team manages it afterward.
# Update the value in console/CLI + force redeploy. No Terraform apply needed.
resource "aws_secretsmanager_secret_version" "env" {
  secret_id = aws_secretsmanager_secret.env.id

  secret_string = jsonencode({
    DB_HOST          = var.db_instance_address
    DB_PORT          = tostring(var.db_instance_port)
    DB_PASSWORD      = random_password.db.result
    REDIS_URL        = "redis://${var.redis_endpoint}:6379"
    SENDGRID_API_KEY = "REPLACE_ME"
    FEATURE_V2_API   = "false"
  })

  lifecycle {
    ignore_changes = [secret_string] # After creation, team manages the value
  }
}

# ---------------------------------------------------------------------------
# ECS Task Definition -- App Reads Secret at Startup
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "main" {
  family                   = var.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name  = var.service_name
    image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${var.service_name}:${var.image_tag}"

    # One env var: the secret name. App reads and parses the JSON at startup.
    environment = [
      {
        name  = "SECRET_NAME"
        value = "/${var.service_name}/env"
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.service_name}"
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = var.service_name
      }
    }
  }])
}

# ---------------------------------------------------------------------------
# IAM -- Task Role Reads the Secret
# ---------------------------------------------------------------------------

# Execution role: only needs ECR pull permissions
resource "aws_iam_role" "task_execution" {
  name = "${var.service_name}-task-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution_ecr" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: reads the secret at runtime (app reads it, not ECS)
resource "aws_iam_role" "task" {
  name = "${var.service_name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "task_secrets" {
  name = "secrets-access"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.env.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [aws_kms_key.secrets.arn]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Infrastructure Wiring (Exception: SSM Parameter Store)
# ---------------------------------------------------------------------------

# Cross-service infrastructure dependencies that change when infra changes
# go in SSM Parameter Store or Terraform remote state -- not the service secret.
# These are consumed by Terraform modules, not by application code directly.

resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/${var.service_name}/infra/db-endpoint"
  type  = "String"
  value = var.db_instance_address

  description = "Database endpoint for ${var.service_name} (infra wiring)"
  tags        = local.tags
}

# ---------------------------------------------------------------------------
# Supporting Resources
# ---------------------------------------------------------------------------

resource "random_password" "db" {
  length  = 32
  special = false # Avoids connection string escaping issues
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  tags = {
    Service   = var.service_name
    ManagedBy = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Key Points
# ---------------------------------------------------------------------------

# 1. ONE secret per service: /{service}/env -- a JSON blob with all env vars
# 2. Account = environment: same path in dev and prod, no env prefix
# 3. Credentials + config together: DB_PASSWORD next to DB_HOST, no separation
# 4. Change without Terraform: update secret value, force redeploy, done
# 5. App reads the secret at startup (task role, not execution role)
# 6. KMS-encrypted with customer-managed key (not provider default)
# 7. IAM scoped to exactly one secret ARN (not a wildcard path)
# 8. Infrastructure wiring (cross-service deps) uses SSM or Terraform remote state
# 9. Image tag is a variable (never :latest)
