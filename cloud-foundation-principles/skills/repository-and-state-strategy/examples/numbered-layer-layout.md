# Numbered Layer Layout

Demonstrates the complete directory structure and backend configuration for a global infrastructure repository using numbered layers. Each layer has its own state file per environment, enabling independent deployment and blast radius containment.

## Directory Structure

```
tf-global-infrastructure/
+-- 00_network/
|   +-- dev/
|   |   +-- main.tf
|   |   +-- vpc.tf
|   |   +-- dns.tf
|   |   +-- endpoints.tf
|   |   +-- backend.tf
|   |   +-- variables.tf
|   |   +-- outputs.tf
|   +-- prod/
|       +-- main.tf
|       +-- vpc.tf
|       +-- dns.tf
|       +-- endpoints.tf
|       +-- backend.tf
|       +-- variables.tf
|       +-- outputs.tf
+-- 10_security/
|   +-- dev/
|   |   +-- main.tf
|   |   +-- security_groups.tf
|   |   +-- kms.tf
|   |   +-- certificates.tf
|   |   +-- backend.tf
|   |   +-- variables.tf
|   |   +-- outputs.tf
|   +-- prod/
|       +-- ...same structure
+-- 20_storage/
|   +-- dev/
|   +-- prod/
+-- 30_databases/
|   +-- dev/
|   +-- prod/
+-- 40_compute/
|   +-- dev/
|   +-- prod/
+-- 50_edge/
|   +-- prod/
+-- 60_messaging/
|   +-- dev/
|   +-- prod/
+-- 70_monitoring/
|   +-- dev/
|   +-- prod/
+-- 80_ci_cd/
+-- 90_shared_services/
|   +-- dev/
|   +-- prod/
+-- scripts/
    +-- plan-all.sh
    +-- apply-layer.sh
```

## Backend Configuration Per Layer

### 00_network/dev/backend.tf

```hcl
terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket = "myorg-dev-tfstate"
    key    = "network"
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

### 10_security/dev/backend.tf

```hcl
terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket = "myorg-dev-tfstate"
    key    = "security"
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

### 40_compute/dev/backend.tf

```hcl
terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket = "myorg-dev-tfstate"
    key    = "compute"
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

## Labels Module Import (Every Layer)

```hcl
# 00_network/dev/main.tf
module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "platform"
  env         = "dev"
  name        = "network"
  cost_center = "infrastructure"
  scope       = "g"
}

locals {
  tags = module.labels.tags
  prefix = module.labels.prefix
}
```

## Output Definitions (Lower Layers Export, Higher Layers Consume)

### 00_network/dev/outputs.tf

```hcl
output "vpc_id" {
  description = "VPC identifier for cross-layer references"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs for compute and database placement"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnet IDs for load balancers and bastion hosts"
  value       = module.vpc.public_subnets
}

output "database_subnet_group_name" {
  description = "Database subnet group for RDS and ElastiCache placement"
  value       = module.vpc.database_subnet_group_name
}

output "dns_zone_id" {
  description = "Public DNS zone ID for service record creation"
  value       = aws_route53_zone.public.zone_id
}

output "internal_dns_zone_id" {
  description = "Private DNS zone ID for internal service discovery"
  value       = aws_route53_zone.internal.zone_id
}
```

### 10_security/dev/outputs.tf

```hcl
output "base_security_group_ids" {
  description = "Default security group IDs applied to all compute resources"
  value       = [aws_security_group.private_base.id]
}

output "wildcard_certificate_arn" {
  description = "Wildcard ACM certificate for HTTPS termination"
  value       = aws_acm_certificate.wildcard.arn
}

output "kms_key_arn" {
  description = "KMS key for encrypting databases and secrets"
  value       = aws_kms_key.main.arn
}
```

## State File Map

```
myorg-dev-tfstate bucket:
  network           <-- 00_network/dev   (VPC, subnets, DNS)
  security          <-- 10_security/dev  (SGs, KMS, certs)
  storage           <-- 20_storage/dev   (S3, EFS)
  databases         <-- 30_databases/dev (RDS, caches)
  compute           <-- 40_compute/dev   (ECS, ASGs)
  messaging         <-- 60_messaging/dev (SQS, SNS, EventBridge)
  monitoring        <-- 70_monitoring/dev (dashboards, alerts)
  shared_services   <-- 90_shared_services/dev

myorg-prod-tfstate bucket:
  network           <-- 00_network/prod
  security          <-- 10_security/prod
  storage           <-- 20_storage/prod
  databases         <-- 30_databases/prod
  compute           <-- 40_compute/prod
  edge              <-- 50_edge/prod
  messaging         <-- 60_messaging/prod
  monitoring        <-- 70_monitoring/prod
  shared_services   <-- 90_shared_services/prod
```

## Key Points

- Each layer directory contains a complete, self-contained Terraform root module per environment
- Backend configuration is explicit in every directory -- no shared backend configuration or workspace tricks
- The state key matches the layer name, making it easy to identify which state file belongs to which layer
- Output definitions are deliberate -- only export what higher layers actually need
- Output descriptions document the intended consumer, not just the value
- The labels module is imported in every layer, ensuring consistent naming and tagging across all infrastructure
