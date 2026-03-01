# Monitoring and Alerting Module

Demonstrates a Terraform monitoring module with sensible defaults, the `-1` disable pattern for optional alarms, and missing-data-safe configurations. Covers compute, database, and HTTP service monitoring.

## Module Interface

```hcl
# tf-module-alerts/variables.tf

variable "service_name" {
  type        = string
  description = "Name of the service being monitored (from labels module)"
}

variable "alarm_emails" {
  type        = list(string)
  description = "Email addresses for alarm notifications"
}

# --- Compute thresholds (sensible defaults) ---

variable "cpu_utilization_threshold" {
  type        = number
  default     = 80
  description = "CPU utilization alarm threshold (%). Set to -1 to disable."
}

variable "memory_utilization_threshold" {
  type        = number
  default     = 85
  description = "Memory utilization alarm threshold (%). Set to -1 to disable."
}

variable "network_in_threshold" {
  type        = number
  default     = -1
  description = "Network bytes in threshold. Disabled by default. Set to -1 to disable."
}

variable "network_out_threshold" {
  type        = number
  default     = -1
  description = "Network bytes out threshold. Disabled by default. Set to -1 to disable."
}

# --- Database thresholds ---

variable "db_cpu_threshold" {
  type        = number
  default     = 80
  description = "Database CPU utilization threshold (%). Set to -1 to disable."
}

variable "db_storage_free_threshold" {
  type        = number
  default     = 10
  description = "Database free storage threshold (GB). Set to -1 to disable."
}

variable "db_connections_threshold" {
  type        = number
  default     = 80
  description = "Database connections threshold (% of max). Set to -1 to disable."
}

variable "db_read_latency_threshold" {
  type        = number
  default     = 0.1
  description = "Database read latency threshold (seconds). Set to -1 to disable."
}

variable "db_write_latency_threshold" {
  type        = number
  default     = 1.0
  description = "Database write latency threshold (seconds). Set to -1 to disable."
}

# --- HTTP thresholds ---

variable "http_5xx_threshold" {
  type        = number
  default     = 1
  description = "HTTP 5xx error rate threshold (%). Set to -1 to disable."
}

variable "http_4xx_threshold" {
  type        = number
  default     = -1
  description = "HTTP 4xx error rate threshold (%). Disabled by default."
}

variable "response_time_threshold" {
  type        = number
  default     = -1
  description = "Response time threshold (seconds). Disabled by default (service-specific)."
}

# --- Resource identifiers (optional, enable monitoring per-resource type) ---

variable "ecs_cluster_name" {
  type        = string
  default     = ""
  description = "ECS cluster name. If empty, ECS alarms are skipped."
}

variable "ecs_service_name" {
  type        = string
  default     = ""
  description = "ECS service name. If empty, ECS alarms are skipped."
}

variable "db_instance_identifier" {
  type        = string
  default     = ""
  description = "RDS instance identifier. If empty, database alarms are skipped."
}

variable "alb_arn_suffix" {
  type        = string
  default     = ""
  description = "ALB ARN suffix. If empty, HTTP alarms are skipped."
}

variable "target_group_arn_suffix" {
  type        = string
  default     = ""
  description = "Target group ARN suffix. If empty, target group alarms are skipped."
}
```

## Module Implementation

```hcl
# tf-module-alerts/main.tf

# --- Conditional creation logic ---

locals {
  # Compute alarms
  create_cpu_alarm     = var.cpu_utilization_threshold >= 0 && var.ecs_cluster_name != ""
  create_memory_alarm  = var.memory_utilization_threshold >= 0 && var.ecs_cluster_name != ""
  create_net_in_alarm  = var.network_in_threshold >= 0 && var.ecs_cluster_name != ""
  create_net_out_alarm = var.network_out_threshold >= 0 && var.ecs_cluster_name != ""

  # Database alarms
  create_db_cpu_alarm         = var.db_cpu_threshold >= 0 && var.db_instance_identifier != ""
  create_db_storage_alarm     = var.db_storage_free_threshold >= 0 && var.db_instance_identifier != ""
  create_db_connections_alarm = var.db_connections_threshold >= 0 && var.db_instance_identifier != ""
  create_db_read_alarm        = var.db_read_latency_threshold >= 0 && var.db_instance_identifier != ""
  create_db_write_alarm       = var.db_write_latency_threshold >= 0 && var.db_instance_identifier != ""

  # HTTP alarms
  create_5xx_alarm           = var.http_5xx_threshold >= 0 && var.alb_arn_suffix != ""
  create_4xx_alarm           = var.http_4xx_threshold >= 0 && var.alb_arn_suffix != ""
  create_response_time_alarm = var.response_time_threshold >= 0 && var.alb_arn_suffix != ""
}

# --- SNS topic for alarm notifications ---

resource "aws_sns_topic" "alerts" {
  name = "${var.service_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alarm_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# --- Compute alarms ---

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = local.create_cpu_alarm ? 1 : 0

  alarm_name          = "${var.service_name}-cpu-high"
  alarm_description   = "CPU utilization exceeds ${var.cpu_utilization_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  # Missing data is NOT a breach -- handles scale-to-zero and spot interruptions
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "memory" {
  count = local.create_memory_alarm ? 1 : 0

  alarm_name          = "${var.service_name}-memory-high"
  alarm_description   = "Memory utilization exceeds ${var.memory_utilization_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_utilization_threshold

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

# --- Database alarms ---

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  count = local.create_db_cpu_alarm ? 1 : 0

  alarm_name          = "${var.service_name}-db-cpu-high"
  alarm_description   = "Database CPU exceeds ${var.db_cpu_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.db_cpu_threshold

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  count = local.create_db_storage_alarm ? 1 : 0

  alarm_name          = "${var.service_name}-db-storage-low"
  alarm_description   = "Database free storage below ${var.db_storage_free_threshold}GB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  # Convert GB to bytes for CloudWatch
  threshold           = var.db_storage_free_threshold * 1024 * 1024 * 1024

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "db_read_latency" {
  count = local.create_db_read_alarm ? 1 : 0

  alarm_name          = "${var.service_name}-db-read-latency-high"
  alarm_description   = "Database read latency exceeds ${var.db_read_latency_threshold}s"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.db_read_latency_threshold

  dimensions = {
    DBInstanceIdentifier = var.db_instance_identifier
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}

# --- HTTP alarms ---

resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  count = local.create_5xx_alarm ? 1 : 0

  alarm_name          = "${var.service_name}-http-5xx-high"
  alarm_description   = "HTTP 5xx error count exceeds threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.http_5xx_threshold

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions      = [aws_sns_topic.alerts.arn]
  treat_missing_data = "notBreaching"
}
```

## Consuming the Module

```hcl
# Service with full monitoring (compute + database + HTTP)
module "alerts" {
  source = "git::https://github.com/myorg/tf-module-alerts.git?ref=v1.3.0"

  service_name = module.labels.prefix
  alarm_emails = ["myapp-team@myorg.com", "oncall@myorg.com"]

  # ECS monitoring
  ecs_cluster_name = "${module.labels.prefix}cluster"
  ecs_service_name = aws_ecs_service.myapp.name

  # Database monitoring
  db_instance_identifier = aws_db_instance.myapp.identifier

  # HTTP monitoring
  alb_arn_suffix          = aws_lb.myapp.arn_suffix
  target_group_arn_suffix = aws_lb_target_group.myapp.arn_suffix

  # Override defaults where needed
  http_5xx_threshold = 0.5  # Stricter for this critical service
  db_storage_free_threshold = 20  # This service has large data volume

  # Disable irrelevant alarms
  network_in_threshold  = -1
  network_out_threshold = -1
}

# Service without a database (compute + HTTP only)
module "alerts_stateless" {
  source = "git::https://github.com/myorg/tf-module-alerts.git?ref=v1.3.0"

  service_name = module.labels.prefix
  alarm_emails = ["frontend-team@myorg.com"]

  ecs_cluster_name = "${module.labels.prefix}cluster"
  ecs_service_name = aws_ecs_service.frontend.name

  alb_arn_suffix          = aws_lb.frontend.arn_suffix
  target_group_arn_suffix = aws_lb_target_group.frontend.arn_suffix

  # No database identifier provided -- all database alarms are automatically skipped
}
```

## Key Points

- Sensible defaults mean every service gets production-grade monitoring with zero configuration effort
- The `-1` sentinel pattern disables individual alarms cleanly without conditional logic in the consuming module
- Resource identifier checks (e.g., `var.db_instance_identifier != ""`) skip entire alarm categories when the resource type is not relevant
- `treat_missing_data = "notBreaching"` prevents alarm storms when services scale to zero or use spot instances
- SNS topics are auto-created per service, so each team gets its own notification channel
- The module uses a consistent interface across all resource types: threshold variable, conditional creation local, alarm resource with count
- Alarms evaluate over multiple periods (2-3) to avoid alerting on transient spikes
