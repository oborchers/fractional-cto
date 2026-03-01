# Wrapper Module

Demonstrates a complete module that wraps a community container service module, adds smart defaults, conditional creation, environment variable injection, and lookup-style outputs. This is a typical "platform module" that service teams consume.

## Directory Structure

```
tf-module-container-service/
+-- main.tf              <-- Wraps community module, applies domain logic
+-- variables.tf         <-- Smart defaults with optional() fields
+-- outputs.tf           <-- Lookup-style outputs keyed by natural identifiers
+-- locals.tf            <-- Complex transformations for containers and target groups
+-- versions.tf          <-- Provider and Terraform version constraints
+-- .pre-commit-config.yaml
+-- .tflint.hcl
+-- README.md
```

## variables.tf -- Smart Defaults

```hcl
variable "create" {
  type        = bool
  default     = true
  description = "Set to false to disable all resource creation"
}

variable "name" {
  type        = string
  description = "Service name (used as resource name prefix)"
}

variable "env" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["dev", "staging", "prod", "security", "log-archive", "sandbox"], var.env)
    error_message = "env must be one of: dev, staging, prod, security, log-archive."
  }
}

variable "cluster_arn" {
  type        = string
  description = "Container cluster ARN from shared compute layer"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID from shared network layer"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for service placement"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Base security group IDs from shared security layer"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags (typically from labels module)"
}

variable "observability_endpoint" {
  type        = string
  default     = ""
  description = "OpenTelemetry collector endpoint for automatic injection"
}

variable "containers" {
  type = list(object({
    name   = string
    image  = string
    cpu    = number
    memory = number

    # Optional with sensible defaults
    port                 = optional(number, 8080)
    desired_count        = optional(number, 2)
    health_check_path    = optional(string, "/health")
    health_check_matcher = optional(string, "200")
    environment = optional(list(object({
      name  = string
      value = string
    })), [])
  }))

  description = "Container definitions. Only name, image, cpu, and memory are required."
}
```

## locals.tf -- Complex Transformations

```hcl
locals {
  # Auto-inject infrastructure environment variables into every container
  container_definitions = [
    for container in var.containers : merge(container, {
      environment = concat(
        coalesce(container.environment, []),
        [
          { name = "SERVICE_NAME",  value = container.name },
          { name = "ENVIRONMENT",   value = var.env },
          { name = "LOG_LEVEL",     value = var.env == "prod" ? "warn" : "debug" },
          { name = "OTEL_ENDPOINT", value = var.observability_endpoint },
        ]
      )
    })
  ]

  # Flatten containers into target group definitions for ALB integration
  target_groups = flatten([
    for container in var.containers : {
      key            = "${container.name}-${container.port}"
      name_prefix    = substr(replace("${container.name}${container.port}", "/[^a-zA-Z0-9]/", ""), 0, 6)
      container_name = container.name
      container_port = container.port
      health_check   = {
        path    = container.health_check_path
        matcher = container.health_check_matcher
      }
    }
  ])

  target_group_map = { for tg in local.target_groups : tg.key => tg }
}
```

## main.tf -- Wrapping Community Module

```hcl
# Wrap the community ECS module -- don't reimplement
module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.0"

  count = var.create ? 1 : 0

  name        = var.name
  cluster_arn = var.cluster_arn

  # Bridge: calculate total CPU/memory from container definitions
  cpu    = sum([for c in var.containers : c.cpu])
  memory = sum([for c in var.containers : c.memory])

  # Network configuration from shared layers
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids

  # Deployment strategy -- organizational standard
  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  wait_for_steady_state              = true

  # Container definitions with injected env vars
  container_definitions = {
    for container in local.container_definitions :
    container.name => {
      image     = container.image
      cpu       = container.cpu
      memory    = container.memory
      essential = true

      port_mappings = [{
        containerPort = container.port
        protocol      = "tcp"
      }]

      environment = container.environment

      health_check = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${container.port}${container.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  }

  tags = var.tags
}

# Target groups for ALB integration
resource "aws_lb_target_group" "this" {
  for_each = var.create ? local.target_group_map : {}

  name_prefix = each.value.name_prefix
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = each.value.health_check.path
    matcher             = each.value.health_check.matcher
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = var.tags
}
```

## outputs.tf -- Lookup-Style Outputs

```hcl
output "service_arn" {
  description = "ECS service ARN"
  value       = var.create ? module.ecs_service[0].service_arn : null
}

output "service_name" {
  description = "ECS service name for CloudWatch metrics"
  value       = var.create ? module.ecs_service[0].service_name : null
}

# Map keyed by natural identifier, not array index
output "target_groups" {
  description = "Target groups keyed by container-port (e.g., 'api-8080')"
  value = {
    for key, tg in aws_lb_target_group.this :
    key => {
      arn  = tg.arn
      name = tg.name
      port = tg.port
    }
  }
}
```

## versions.tf

```hcl
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

## Consumer Usage

```hcl
# Minimal: only 4 required fields per container
module "api_service" {
  source = "git::https://github.com/myorg/tf-module-container-service.git?ref=v2.0.0"

  name               = "${module.labels.prefix}api"
  env                = "dev"
  cluster_arn        = data.terraform_remote_state.compute.outputs.ecs_cluster_arn
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  subnet_ids         = data.terraform_remote_state.network.outputs.private_subnets
  security_group_ids = data.terraform_remote_state.security.outputs.base_security_group_ids
  tags               = module.labels.tags

  observability_endpoint = "http://otel-collector.internal:4317"

  containers = [{
    name   = "api"
    image  = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/myapp-api:abc1234"
    cpu    = 1024
    memory = 2048
    environment = [
      { name = "DATABASE_URL", value = "postgres://db.internal:5432/myapp" },
    ]
    # port=8080, health_check_path="/health", desired_count=2 are all defaults
  }]
}

# Reference outputs by natural key
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = module.api_service.target_groups["api-8080"].arn
  }

  condition {
    host_header {
      values = ["api.dev.myorg.com"]
    }
  }
}
```

## Key Points

- The module wraps `terraform-aws-modules/ecs` rather than reimplementing ECS service management
- Only 4 fields per container are required; all others have sensible defaults
- Infrastructure environment variables (SERVICE_NAME, ENVIRONMENT, LOG_LEVEL, OTEL_ENDPOINT) are injected automatically
- Target groups are output as a map keyed by `container-port`, not as an array
- The `create` variable allows the entire module to be toggled off
- Deployment strategy (circuit breaker, rolling updates) encodes organizational standards
- Complex container and target group transformations live in `locals`, not inline
