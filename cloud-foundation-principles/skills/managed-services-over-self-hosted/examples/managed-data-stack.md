# Managed Data Stack
#
# Production-grade managed database and cache with automated operations.
# Contrasts against self-hosted equivalents to illustrate the operations tax.
#
# Managed services provide: backups, failover, patching, encryption,
# monitoring, and scaling -- all without a single cron job or runbook.

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "service_name" {
  description = "Service identifier"
  type        = string
  default     = "myapp"
}

variable "vpc_id" {
  description = "VPC ID from network layer"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from network layer"
  type        = list(string)
}

variable "database_subnet_group_name" {
  description = "Database subnet group from network layer"
  type        = string
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "product"
  env         = "dev"  # Change per environment directory
  name        = var.service_name
  cost_center = "engineering"
}

locals {
  is_prod = module.labels.env == "prod"
}

# ---------------------------------------------------------------------------
# Managed PostgreSQL -- All Operations Automated
# ---------------------------------------------------------------------------

# What you get for free:
#   - Automated daily backups with point-in-time recovery (14 days in prod)
#   - Multi-AZ failover with automatic DNS failover (prod)
#   - Minor version patches applied automatically
#   - Storage encryption with KMS
#   - Performance monitoring (Performance Insights)
#   - Connection pooling metrics
#   - Deletion protection (prod)
#
# What you would need to build yourself with self-hosted PostgreSQL:
#   - pg_basebackup + WAL archiving + pgBackRest configuration
#   - Streaming replication + Patroni or repmgr for HA
#   - Cron job for pg_dump verification
#   - Custom monitoring for replication lag, connections, disk, memory
#   - Manual failover runbooks or custom automation
#   - OS patching schedule + PostgreSQL patch testing
#   - SSL certificate management for connections
#   - Storage management and VACUUM tuning

resource "aws_db_instance" "main" {
  identifier = "${module.labels.prefix}${var.service_name}"

  # Engine
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = local.is_prod ? "db.r6g.large" : "db.t4g.medium"
  parameter_group_name = aws_db_parameter_group.main.name

  # Storage
  allocated_storage     = 20
  max_allocated_storage = local.is_prod ? 200 : 50 # Auto-scaling storage
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.database.arn

  # Database
  db_name  = var.service_name
  username = "${var.service_name}_root"
  password = random_password.db_root.result

  # High availability: automatic failover in production
  multi_az = local.is_prod

  # Backups: automated with point-in-time recovery
  backup_retention_period = local.is_prod ? 14 : 3
  backup_window           = "03:00-04:00"

  # Maintenance: automatic minor version upgrades
  auto_minor_version_upgrade = true
  maintenance_window         = "sun:04:00-sun:05:00"

  # Monitoring: built-in performance insights
  performance_insights_enabled          = true
  performance_insights_retention_period = local.is_prod ? 731 : 7 # 2 years prod, 7 days dev
  monitoring_interval                   = local.is_prod ? 30 : 0   # Enhanced monitoring in prod
  monitoring_role_arn                   = local.is_prod ? aws_iam_role.rds_monitoring[0].arn : null

  # Network
  db_subnet_group_name   = var.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false # Never public

  # Protection
  deletion_protection = local.is_prod
  skip_final_snapshot = !local.is_prod
  final_snapshot_identifier = local.is_prod ? "${module.labels.prefix}${var.service_name}-final" : null

  tags = module.labels.tags
}

resource "aws_db_parameter_group" "main" {
  name   = "${module.labels.prefix}${var.service_name}-pg15"
  family = "postgres15"

  # Log slow queries for debugging (managed monitoring, no custom setup needed)
  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries taking longer than 1 second
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }
}

# ---------------------------------------------------------------------------
# Managed Redis Cache -- All Operations Automated
# ---------------------------------------------------------------------------

# What you get for free:
#   - Automatic failover with read replicas (prod)
#   - Automated backups and snapshots
#   - Patching without downtime
#   - Encryption at rest and in transit
#   - CloudWatch metrics for evictions, memory, CPU, connections
#
# What you would need to build yourself with self-hosted Redis:
#   - Redis Sentinel or Redis Cluster for HA
#   - Custom backup scripts (BGSAVE + S3 upload)
#   - OS patching + Redis version upgrades
#   - Monitoring: redis-exporter + Prometheus + Grafana
#   - Memory management and eviction policy tuning
#   - TLS certificate management
#   - Custom failover runbooks

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${module.labels.prefix}${var.service_name}"
  description          = "Redis cache for ${var.service_name}"

  # Engine
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = local.is_prod ? "cache.r6g.large" : "cache.t4g.medium"
  parameter_group_name = "default.redis7"

  # High availability: automatic failover with replicas in production
  automatic_failover_enabled = local.is_prod
  num_cache_clusters         = local.is_prod ? 2 : 1 # Primary + replica in prod

  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = aws_kms_key.cache.arn

  # Backups
  snapshot_retention_limit = local.is_prod ? 7 : 1
  snapshot_window          = "03:00-04:00"

  # Maintenance
  maintenance_window = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade = true

  # Network
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.cache.id]

  tags = module.labels.tags
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${module.labels.prefix}${var.service_name}-cache"
  subnet_ids = var.private_subnet_ids
}

# ---------------------------------------------------------------------------
# Managed Monitoring -- CloudWatch Alarms (no Prometheus/Grafana to maintain)
# ---------------------------------------------------------------------------

# Database alarms
resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${module.labels.prefix}${var.service_name}-db-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Database CPU > 80% for 15 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${module.labels.prefix}${var.service_name}-db-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Minimum"
  threshold           = 5368709120 # 5 GB in bytes
  alarm_description   = "Database free storage < 5 GB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${module.labels.prefix}${var.service_name}-db-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Database connections > 80 for 10 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }
}

# Cache alarms
resource "aws_cloudwatch_metric_alarm" "cache_evictions" {
  alarm_name          = "${module.labels.prefix}${var.service_name}-cache-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "Cache evictions > 100 in 15 minutes (memory pressure)"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "cache_memory" {
  alarm_name          = "${module.labels.prefix}${var.service_name}-cache-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Cache memory usage > 80% for 10 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }
}

# ---------------------------------------------------------------------------
# Encryption Keys
# ---------------------------------------------------------------------------

resource "aws_kms_key" "database" {
  description         = "Encryption key for ${var.service_name} database"
  enable_key_rotation = true
}

resource "aws_kms_key" "cache" {
  description         = "Encryption key for ${var.service_name} cache"
  enable_key_rotation = true
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "database" {
  name   = "${module.labels.prefix}${var.service_name}-db"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block] # VPC CIDR only
    description = "PostgreSQL from VPC"
  }

  tags = merge(module.labels.tags, { Name = "${module.labels.prefix}${var.service_name}-db" })
}

resource "aws_security_group" "cache" {
  name   = "${module.labels.prefix}${var.service_name}-cache"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
    description = "Redis from VPC"
  }

  tags = merge(module.labels.tags, { Name = "${module.labels.prefix}${var.service_name}-cache" })
}

# ---------------------------------------------------------------------------
# Supporting Resources
# ---------------------------------------------------------------------------

resource "random_password" "db_root" {
  length  = 32
  special = false
}

resource "aws_iam_role" "rds_monitoring" {
  count = local.is_prod ? 1 : 0
  name  = "${module.labels.prefix}${var.service_name}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count      = local.is_prod ? 1 : 0
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_vpc" "main" {
  id = var.vpc_id
}

# ---------------------------------------------------------------------------
# Key Points
# ---------------------------------------------------------------------------

# 1. Managed PostgreSQL: backups, failover, patching, encryption, monitoring
#    all handled by the provider. Zero cron jobs, zero runbooks.
# 2. Managed Redis: automatic failover, snapshots, patching, encryption.
#    No Redis Sentinel, no custom backup scripts.
# 3. Managed monitoring: CloudWatch alarms with sensible defaults.
#    No Prometheus + Grafana + Alertmanager to deploy and maintain.
# 4. Production gets: Multi-AZ, longer backups, enhanced monitoring,
#    deletion protection. Dev gets: smaller instances, shorter retention.
# 5. Auto-scaling storage: database storage grows automatically up to max.
# 6. Performance Insights: query-level monitoring built in, no pg_stat setup.
# 7. All encryption uses customer-managed KMS keys with auto-rotation.
# 8. The self-hosted equivalent of this file would require 3-5x more code
#    plus backup scripts, monitoring configs, HA setup, and patching runbooks.
