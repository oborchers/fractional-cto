# Shared Module Contract

Demonstrates a shared container service module that encodes organizational standards (naming, deployment strategy, health checks, monitoring hooks) while allowing service teams to override defaults. This is the module the platform team provides; service teams consume it.

## Module Interface

```hcl
# tf-module-container-service/variables.tf

variable "name" {
  type        = string
  description = "Service name (from labels module prefix)"
}

variable "cluster_arn" {
  type        = string
  description = "ARN of the shared container cluster"
}

variable "image" {
  type        = string
  description = "Full container image URI with tag (e.g., registry/myapp:a1b2c3d)"
}

variable "cpu" {
  type        = number
  default     = 1024
  description = "CPU units (256, 512, 1024, 2048, 4096)"

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096"
  }
}

variable "memory" {
  type        = number
  default     = 2048
  description = "Memory in MB"
}

variable "desired_count" {
  type        = number
  default     = 2
  description = "Number of running instances"
}

variable "container_port" {
  type        = number
  default     = 3000
  description = "Port the container listens on"
}

variable "health_check_path" {
  type        = string
  default     = "/health"
  description = "HTTP path for health checks"
}

variable "health_check_interval" {
  type        = number
  default     = 30
  description = "Seconds between health checks"
}

variable "subnets" {
  type        = list(string)
  description = "Subnet IDs for the service"
}

variable "security_groups" {
  type        = list(string)
  description = "Security group IDs"
}

# --- Deployment strategy (opinionated defaults) ---

variable "enable_circuit_breaker" {
  type        = bool
  default     = true
  description = "Enable deployment circuit breaker with auto-rollback"
}

variable "deployment_maximum_percent" {
  type        = number
  default     = 200
  description = "Maximum percent of desired count during deployment"
}

variable "deployment_minimum_healthy_percent" {
  type        = number
  default     = 100
  description = "Minimum healthy percent during deployment"
}

variable "wait_for_steady_state" {
  type        = bool
  default     = true
  description = "Block Terraform until service reaches steady state"
}

# --- Optional features ---

variable "environment_variables" {
  type        = map(string)
  default     = {}
  description = "Environment variables passed to the container (include SECRET_NAME for secrets)"
}

variable "log_retention_days" {
  type        = number
  default     = 14
  description = "CloudWatch log retention in days"
}

variable "enable_autoscaling" {
  type        = bool
  default     = false
  description = "Enable CPU-based autoscaling"
}

variable "autoscaling_min" {
  type        = number
  default     = 2
  description = "Minimum number of tasks when autoscaling is enabled"
}

variable "autoscaling_max" {
  type        = number
  default     = 10
  description = "Maximum number of tasks when autoscaling is enabled"
}

variable "autoscaling_cpu_target" {
  type        = number
  default     = 70
  description = "Target CPU utilization percentage for autoscaling"
}
```

## Module Implementation

```hcl
# tf-module-container-service/main.tf

# --- Log group (always created with retention) ---

resource "aws_cloudwatch_log_group" "service" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
}

# --- Task definition ---

resource "aws_ecs_task_definition" "service" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name  = var.name
    image = var.image
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      interval    = var.health_check_interval
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.service.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = var.name
      }
    }
    # App reads secrets at startup via SECRET_NAME env var
    # (see secrets-and-configuration-management skill)
    environment = [
      for k, v in var.environment_variables : {
        name  = k
        value = v
      }
    ]
  }])
}

# --- ECS service with opinionated deployment strategy ---

resource "aws_ecs_service" "service" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.subnets
    security_groups = var.security_groups
  }

  # Opinionated: circuit breaker is always on by default
  dynamic "deployment_circuit_breaker" {
    for_each = var.enable_circuit_breaker ? [1] : []
    content {
      enable   = true
      rollback = true
    }
  }

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  wait_for_steady_state              = var.wait_for_steady_state
}

# --- Autoscaling (optional) ---

resource "aws_appautoscaling_target" "service" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.autoscaling_max
  min_capacity       = var.autoscaling_min
  resource_id        = "service/${split("/", var.cluster_arn)[1]}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = var.autoscaling_cpu_target
  }
}

data "aws_region" "current" {}
```

## Consuming the Module (Service Team)

```hcl
# In the service repository: infrastructure/dev/service.tf

module "myapp_service" {
  source = "git::https://github.com/myorg/tf-module-container-service.git?ref=v2.1.0"

  name        = module.labels.prefix
  cluster_arn = local.cluster_arn
  image       = "${local.registry_url}/myapp-api:${var.image_tag}"
  cpu         = 1024
  memory      = 2048

  subnets         = local.private_subnets
  security_groups = local.base_sg_ids

  health_check_path = "/health"
  desired_count     = 2

  environment_variables = {
    SECRET_NAME = "/myapp-api/env"
    PORT        = "3000"
  }

  # All deployment defaults (circuit breaker, rolling update, wait for steady
  # state) are inherited from the module. Override only when justified.
}
```

## Key Points

- The module encodes organizational standards: circuit breaker deployments, rolling updates, log retention, and health check patterns are built in
- Service teams write 15-20 lines of module invocation instead of 100+ lines of raw resource definitions
- Defaults are production-safe: `enable_circuit_breaker = true`, `wait_for_steady_state = true`, `deployment_minimum_healthy_percent = 100`
- Input validation prevents misconfiguration: CPU must be a valid Fargate value, rejected at plan time
- Optional features (autoscaling) are disabled by default and enabled per-service
- The module is pinned with `?ref=v2.1.0` so upgrades are explicit, not accidental
- Log groups always have explicit retention (no "retain forever" default)
