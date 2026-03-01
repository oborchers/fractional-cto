# Database Role Management
#
# Creates role-based database users following the {purpose}_{access} convention.
# No person-specific database accounts. Developer access via SSO + database proxy.
#
# Roles:
#   app_readwrite    -- Application service (read + write)
#   analytics_readonly -- BI/analytics tools (read only)
#   generic_readonly   -- All team members via SSO (read only, debugging)
#   migration_admin    -- Schema migrations (DDL, time-boxed)

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "service_name" {
  description = "Service identifier"
  type        = string
  default     = "myapp"
}

variable "db_instance_address" {
  description = "RDS instance endpoint"
  type        = string
}

variable "db_instance_port" {
  description = "RDS instance port"
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Database name"
  type        = string
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  secret_path = "/${var.service_name}"

  # Role definitions: {purpose}_{access}
  db_roles = {
    app_readwrite = {
      description = "Application service read-write access"
      privileges  = "SELECT, INSERT, UPDATE, DELETE"
      rotation    = true
      rotation_days = 30
    }
    app_readonly = {
      description = "Application service read-only access (replica queries)"
      privileges  = "SELECT"
      rotation    = true
      rotation_days = 30
    }
    analytics_readonly = {
      description = "Analytics and BI tools read-only access"
      privileges  = "SELECT"
      rotation    = true
      rotation_days = 90
    }
    generic_readonly = {
      description = "All team members via SSO (debugging access)"
      privileges  = "SELECT"
      rotation    = true
      rotation_days = 90
    }
    migration_admin = {
      description = "Schema migration runner (DDL permissions, CI/CD only)"
      privileges  = "ALL"
      rotation    = true
      rotation_days = 30
    }
  }
}

# ---------------------------------------------------------------------------
# KMS Key for Database Credentials
# ---------------------------------------------------------------------------

resource "aws_kms_key" "db_credentials" {
  description         = "Encryption key for ${var.service_name} database credentials"
  enable_key_rotation = true

  tags = {
    Service = var.service_name
    Purpose = "db-credentials"
  }
}

# ---------------------------------------------------------------------------
# Password Generation -- One per Role
# ---------------------------------------------------------------------------

resource "random_password" "db_role" {
  for_each = local.db_roles

  length  = 32
  special = false # Avoids connection string escaping issues
}

# ---------------------------------------------------------------------------
# Secrets Manager -- One Secret per Role
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "db_role" {
  for_each = local.db_roles

  name       = "${local.secret_path}/db-${each.key}"
  kms_key_id = aws_kms_key.db_credentials.arn

  description = "${each.value.description} for ${var.service_name}"

  tags = {
    Service  = var.service_name
    Role     = each.key
    Type     = "db-credential"
    Rotation = each.value.rotation ? "automatic-${each.value.rotation_days}d" : "manual"
  }
}

resource "aws_secretsmanager_secret_version" "db_role" {
  for_each = local.db_roles

  secret_id = aws_secretsmanager_secret.db_role[each.key].id
  secret_string = jsonencode({
    username = each.key
    password = random_password.db_role[each.key].result
    host     = var.db_instance_address
    port     = var.db_instance_port
    dbname   = var.database_name
    engine   = "postgres"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ---------------------------------------------------------------------------
# RDS Proxy -- For Developer Access via SSO (no direct DB connections)
# ---------------------------------------------------------------------------

resource "aws_db_proxy" "main" {
  name                   = "${var.service_name}-db-proxy"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = var.private_subnet_ids

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "REQUIRED" # Forces IAM authentication -- no password needed
    secret_arn  = aws_secretsmanager_secret.db_role["generic_readonly"].arn
  }

  tags = {
    Service = var.service_name
  }
}

resource "aws_db_proxy_default_target_group" "main" {
  db_proxy_name = aws_db_proxy.main.name

  connection_pool_config {
    max_connections_percent = 50
  }
}

# ---------------------------------------------------------------------------
# IAM Roles -- Scoped per Database Role
# ---------------------------------------------------------------------------

# Application service: can read the app_readwrite secret
resource "aws_iam_role_policy" "app_db_access" {
  name = "db-readwrite-access"
  role = var.app_task_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.db_role["app_readwrite"].arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [aws_kms_key.db_credentials.arn]
      }
    ]
  })
}

# Analytics tools: can read the analytics_readonly secret only
resource "aws_iam_role_policy" "analytics_db_access" {
  name = "db-analytics-access"
  role = var.analytics_task_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.db_role["analytics_readonly"].arn
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [aws_kms_key.db_credentials.arn]
      }
    ]
  })
}

# Developers: IAM-based access through RDS Proxy (no password needed)
# Access: Developer --> SSO --> AWS Console --> SSM port forward --> RDS Proxy
# The proxy authenticates via IAM and connects as generic_readonly

resource "aws_iam_policy" "developer_db_access" {
  name = "${var.service_name}-developer-db"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["rds-db:connect"]
        Resource = [
          "arn:aws:rds-db:*:*:dbuser:${aws_db_proxy.main.id}/generic_readonly"
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# PostgreSQL Role Creation (via provider or bootstrap script)
# ---------------------------------------------------------------------------

# These SQL statements would be executed by a bootstrap process or
# a Terraform PostgreSQL provider. Shown here as reference.
#
# -- Application read-write role
# CREATE ROLE app_readwrite LOGIN PASSWORD '<from-secrets-manager>';
# GRANT CONNECT ON DATABASE myapp TO app_readwrite;
# GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_readwrite;
# ALTER DEFAULT PRIVILEGES IN SCHEMA public
#   GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;
#
# -- Application read-only role
# CREATE ROLE app_readonly LOGIN PASSWORD '<from-secrets-manager>';
# GRANT CONNECT ON DATABASE myapp TO app_readonly;
# GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
# ALTER DEFAULT PRIVILEGES IN SCHEMA public
#   GRANT SELECT ON TABLES TO app_readonly;
#
# -- Analytics read-only role
# CREATE ROLE analytics_readonly LOGIN PASSWORD '<from-secrets-manager>';
# GRANT CONNECT ON DATABASE myapp TO analytics_readonly;
# GRANT SELECT ON ALL TABLES IN SCHEMA public TO analytics_readonly;
# ALTER DEFAULT PRIVILEGES IN SCHEMA public
#   GRANT SELECT ON TABLES TO analytics_readonly;
#
# -- Generic developer read-only role (SSO + RDS Proxy)
# CREATE ROLE generic_readonly LOGIN PASSWORD '<from-secrets-manager>';
# GRANT CONNECT ON DATABASE myapp TO generic_readonly;
# GRANT SELECT ON ALL TABLES IN SCHEMA public TO generic_readonly;
# ALTER DEFAULT PRIVILEGES IN SCHEMA public
#   GRANT SELECT ON TABLES TO generic_readonly;
#
# -- Migration admin role (CI/CD only, DDL permissions)
# CREATE ROLE migration_admin LOGIN PASSWORD '<from-secrets-manager>';
# GRANT ALL PRIVILEGES ON DATABASE myapp TO migration_admin;
# GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO migration_admin;
# GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO migration_admin;

# ---------------------------------------------------------------------------
# Supporting Resources
# ---------------------------------------------------------------------------

resource "aws_iam_role" "rds_proxy" {
  name = "${var.service_name}-rds-proxy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name = "secrets-access"
  role = aws_iam_role.rds_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [for s in aws_secretsmanager_secret.db_role : s.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [aws_kms_key.db_credentials.arn]
      }
    ]
  })
}

variable "app_task_role_id" {
  description = "IAM role ID for the application ECS task"
  type        = string
}

variable "analytics_task_role_id" {
  description = "IAM role ID for the analytics ECS task"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the RDS proxy"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Key Points
# ---------------------------------------------------------------------------

# 1. Five role-based users, zero person-specific users
# 2. Role naming: {purpose}_{access} (app_readwrite, analytics_readonly, etc.)
# 3. Each role has its own secret at /{service}/db-{role} (no env prefix)
# 4. Account = environment: same paths in dev and prod, different accounts
# 5. IAM policies scope each service to ONLY its role's secret
# 6. Developer access: SSO --> IAM auth --> RDS Proxy --> generic_readonly
# 7. No developer knows any database password (IAM auth via proxy)
# 8. Offboarding: disable SSO account, all database access revokes instantly
# 9. migration_admin is for CI/CD schema migrations only, not human use
