# Managed Container Service Deployment
#
# Complete managed container deployment with:
#   - Spot/preemptible capacity for cost savings
#   - Circuit breaker with auto-rollback
#   - Application auto-scaling (CPU + request count)
#   - Zero-downtime rolling updates
#   - No cluster management, no node patching, no CNI plugins
#
# Compare with self-managed Kubernetes which requires:
#   cluster upgrades, node groups, ingress controllers, cert-manager,
#   metrics-server, cluster-autoscaler, and someone to maintain them all.

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "service_name" {
  description = "Service identifier"
  type        = string
  default     = "myapp"
}

variable "container_image" {
  description = "Container image URI with tag (use git SHA, not 'latest')"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU units (256 = 0.25 vCPU, 1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memory in MiB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "health_check_path" {
  description = "Health check endpoint path"
  type        = string
  default     = "/health"
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
# ECS Service -- Managed Container Deployment
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "main" {
  name            = "${module.labels.prefix}${var.service_name}"
  cluster         = data.terraform_remote_state.compute.outputs.cluster_arn
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count

  # Managed capacity: Fargate (no EC2 instances to patch or scale)
  # Split between on-demand and spot for cost optimization
  # Adjust weights based on your availability requirements and budget
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = local.is_prod ? 70 : 30 # Prod favors on-demand for stability
    base              = 1                         # At least 1 on-demand task always
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = local.is_prod ? 30 : 70 # Dev favors spot for cost savings
  }

  # Circuit breaker: auto-rollback on failed deployments
  # If the new task definition fails health checks, ECS rolls back automatically
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Zero-downtime rolling update
  # 200% max: new tasks start before old tasks stop
  # 100% min: all current tasks stay healthy during deployment
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  # Wait for the service to stabilize before Terraform reports success
  wait_for_steady_state = true

  network_configuration {
    subnets         = data.terraform_remote_state.network.outputs.private_subnet_ids
    security_groups = [aws_security_group.service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  # Ignore desired_count changes made by auto-scaling
  lifecycle {
    ignore_changes = [desired_count]
  }
}

# ---------------------------------------------------------------------------
# Task Definition
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "main" {
  family                   = "${module.labels.prefix}${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = var.service_name
    image     = var.container_image # e.g., "123456789012.dkr.ecr.eu-west-1.amazonaws.com/myapp:a1b2c3d"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${module.labels.prefix}${var.service_name}"
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = var.service_name
      }
    }
  }])
}

# ---------------------------------------------------------------------------
# Auto-Scaling -- CPU and Request Count Based
# ---------------------------------------------------------------------------

resource "aws_appautoscaling_target" "main" {
  max_capacity       = local.is_prod ? 10 : 4
  min_capacity       = local.is_prod ? 2 : 1
  resource_id        = "service/${data.terraform_remote_state.compute.outputs.cluster_name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Scale on CPU utilization
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${module.labels.prefix}${var.service_name}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.main.resource_id
  scalable_dimension = aws_appautoscaling_target.main.scalable_dimension
  service_namespace  = aws_appautoscaling_target.main.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Scale on request count per target -- tune target_value based on your service's
# throughput capacity (start high, lower if latency degrades under load)
resource "aws_appautoscaling_policy" "requests" {
  name               = "${module.labels.prefix}${var.service_name}-requests"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.main.resource_id
  scalable_dimension = aws_appautoscaling_target.main.scalable_dimension
  service_namespace  = aws_appautoscaling_target.main.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.main.arn_suffix}"
    }
    target_value       = 1000.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# ---------------------------------------------------------------------------
# Load Balancer Target Group
# ---------------------------------------------------------------------------

resource "aws_lb_target_group" "main" {
  name        = "${module.labels.prefix}${var.service_name}"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  deregistration_delay = 30
}

# ---------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------

resource "aws_security_group" "service" {
  name   = "${module.labels.prefix}${var.service_name}"
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.network.outputs.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# IAM Roles
# ---------------------------------------------------------------------------

resource "aws_iam_role" "execution" {
  name = "${module.labels.prefix}${var.service_name}-exec"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${module.labels.prefix}${var.service_name}-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/${module.labels.prefix}${var.service_name}"
  retention_in_days = local.is_prod ? 90 : 14
}

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

data "aws_region" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"  # Convention: <org>-<env>-tfstate
    key    = "network"
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"  # Convention: <org>-<env>-tfstate
    key    = "compute"
  }
}

# Placeholder: referenced by auto-scaling request count policy
data "aws_lb" "main" {
  name = "${module.labels.prefix}-alb"
}

resource "aws_lb" "main" {
  name = data.aws_lb.main.name
  # In practice, the ALB is defined in the network/compute layer
  # and referenced here via remote state. Shown for completeness.
}

# ---------------------------------------------------------------------------
# Key Points
# ---------------------------------------------------------------------------

# 1. FARGATE + FARGATE_SPOT: no EC2 instances, no node patching, no AMI updates
# 2. Circuit breaker: failed deployments auto-rollback (no manual intervention)
# 3. Rolling update: 200% max / 100% min = zero downtime during deploys
# 4. Auto-scaling on CPU and request count with separate cooldown periods
# 5. Prod: 70% on-demand / 30% spot (stability). Dev: 30/70 (cost savings)
# 6. wait_for_steady_state: Terraform blocks until service is healthy
# 7. Container image tagged with git SHA for full traceability
# 8. Total infrastructure management overhead: zero (provider handles everything)
