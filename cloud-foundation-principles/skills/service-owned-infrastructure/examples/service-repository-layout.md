# Service Repository Layout

Demonstrates a complete service repository with infrastructure-as-code alongside application code. The service consumes shared infrastructure (VPC, cluster, security groups) via remote state and defines its own resources (container service, load balancer rules, DNS records, alerts).

## Directory Structure

```
myapp-api/
├── src/
│   └── ...                        # Application source code
├── Dockerfile
├── infrastructure/
│   ├── dev/
│   │   ├── backend.tf
│   │   ├── main.tf
│   │   ├── service.tf
│   │   ├── loadbalancer.tf
│   │   ├── dns.tf
│   │   ├── secrets.tf
│   │   ├── alerts.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── prod/
│       └── ...same files, different values
└── .github/workflows/
    ├── ci.yml
    └── cd.yml
```

## Terraform Configuration

### backend.tf -- State Isolation

```hcl
terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket       = "myorg-dev-tfstate"
    key          = "myapp-api"
    region       = "eu-west-1"
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = module.labels.tags
  }
}
```

### main.tf -- Labels and Remote State

```hcl
# Consistent naming and tagging across the organization
module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "product"
  env         = "dev"
  name        = "myapp-api"
  cost_center = "engineering"
}

# --- Shared infrastructure references ---

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "network"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "security"
    region = "eu-west-1"
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "compute"
    region = "eu-west-1"
  }
}

# --- Local references for readability ---

locals {
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  private_subnets     = data.terraform_remote_state.network.outputs.private_subnets
  public_subnets      = data.terraform_remote_state.network.outputs.public_subnets
  db_subnet_group     = data.terraform_remote_state.network.outputs.database_subnet_group_name
  dns_zone_id         = data.terraform_remote_state.network.outputs.dns_zone_id
  internal_zone_id    = data.terraform_remote_state.network.outputs.internal_dns_zone_id
  cluster_arn         = data.terraform_remote_state.compute.outputs.ecs_cluster_arn
  base_sg_ids         = data.terraform_remote_state.security.outputs.base_security_group_ids
  certificate_arn     = data.terraform_remote_state.security.outputs.wildcard_certificate_arn
  registry_url        = "123456789012.dkr.ecr.eu-west-1.amazonaws.com"
}
```

### service.tf -- Container Service Definition

```hcl
# Container image repository (service-owned)
resource "aws_ecr_repository" "myapp" {
  name                 = "${module.labels.prefix}myapp-api"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "myapp" {
  repository = aws_ecr_repository.myapp.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 tagged images"
      selection = {
        tagStatus   = "tagged"
        tagPrefixList = [""]
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

# ECS task definition (service-owned)
resource "aws_ecs_task_definition" "myapp" {
  family                   = "${module.labels.prefix}myapp-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name  = "myapp-api"
    image = "${aws_ecr_repository.myapp.repository_url}:${var.image_tag}"
    portMappings = [{
      containerPort = 3000
      protocol      = "tcp"
    }]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.myapp.name
        "awslogs-region"        = "eu-west-1"
        "awslogs-stream-prefix" = "myapp-api"
      }
    }
    # App reads the secret at startup (see secrets-and-configuration-management skill)
    environment = [
      {
        name  = "SECRET_NAME"
        value = "/myapp-api/env"
      }
    ]
  }])
}

# ECS service (service-owned)
resource "aws_ecs_service" "myapp" {
  name            = "${module.labels.prefix}myapp-api"
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.myapp.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = local.private_subnets
    security_groups = local.base_sg_ids
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.myapp.arn
    container_name   = "myapp-api"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  wait_for_steady_state              = true
}

# Log group with explicit retention
resource "aws_cloudwatch_log_group" "myapp" {
  name              = "/ecs/${module.labels.prefix}myapp-api"
  retention_in_days = 14
}
```

### alerts.tf -- Service-Specific Monitoring

```hcl
module "alerts" {
  source = "git::https://github.com/myorg/tf-module-alerts.git?ref=v1.3.0"

  service_name            = "${module.labels.prefix}myapp-api"
  alarm_emails            = ["myapp-team@myorg.com"]
  ecs_cluster_name        = "${module.labels.prefix}cluster"
  ecs_service_name        = aws_ecs_service.myapp.name
  cpu_utilization_threshold = 80
  memory_utilization_threshold = 85

  # Disable network alerts (not relevant for this service)
  network_in_threshold  = -1
  network_out_threshold = -1
}
```

### variables.tf

```hcl
variable "image_tag" {
  type        = string
  description = "Container image tag (git SHA)"

  validation {
    condition     = can(regex("^[a-f0-9]{7,40}$", var.image_tag))
    error_message = "image_tag must be a git SHA (7-40 hex characters)"
  }
}
```

## Key Points

- The service repository contains all infrastructure needed to deploy the service independently
- Shared infrastructure (VPC, cluster, security groups) is consumed via `terraform_remote_state`, never duplicated
- The service has its own state file (`key = "myapp-api"`) isolated from all other services
- The labels module provides consistent naming and tagging across the organization
- Container images use immutable tags and lifecycle policies for cleanup
- Monitoring is attached from day one using the shared alerts module
- The `image_tag` variable is validated to ensure it is a git SHA
