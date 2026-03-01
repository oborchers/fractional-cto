# Example: VPC with Subnet Tiers and Private Connectivity

## Complete VPC Configuration (00_network/prod/main.tf)

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

provider "aws" {
  region = var.region
  default_tags {
    tags = local.tags
  }
}

module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "platform"
  env         = "prod"
  name        = "network"
  cost_center = "infrastructure"
}

locals {
  tags   = module.labels.tags
  prefix = module.labels.prefix
  azs    = ["${var.region}a", "${var.region}b", "${var.region}c"]
}

# ---------------------------------------------------------------------------
# VPC with subnet tiers across three availability zones
# This example shows all five tiers; omit cache/warehouse if not needed
# ---------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "${local.prefix}vpc"
  cidr = "10.10.0.0/16"

  # Secondary CIDRs reserved for future expansion
  secondary_cidr_blocks = ["10.11.0.0/16", "10.12.0.0/16"]

  azs = local.azs

  # Tier 1: Public (load balancers, NAT gateways)
  public_subnets = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]

  # Tier 2: Private (application workloads)
  private_subnets = ["10.10.11.0/24", "10.10.12.0/24", "10.10.13.0/24"]

  # Tier 3: Database (managed SQL databases)
  database_subnets = ["10.10.21.0/24", "10.10.22.0/24", "10.10.23.0/24"]
  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  # Tier 4 (optional): Cache (Redis, Memcached) -- add when using managed caches
  elasticache_subnets = ["10.10.31.0/24", "10.10.32.0/24", "10.10.33.0/24"]
  create_elasticache_subnet_group = true

  # Tier 5 (optional): Warehouse (analytical databases) -- add when running data warehouses
  redshift_subnets = ["10.10.41.0/24", "10.10.42.0/24", "10.10.43.0/24"]
  create_redshift_subnet_group = true

  # DNS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # NAT: single gateway for cost optimization
  # Switch to one_nat_gateway_per_az = true when SLA requires AZ redundancy
  enable_nat_gateway = true
  single_nat_gateway = true

  # Tags for subnet identification
  public_subnet_tags = {
    "tier" = "public"
  }
  private_subnet_tags = {
    "tier" = "private"
  }
  database_subnet_tags = {
    "tier" = "database"
  }
  elasticache_subnet_tags = {
    "tier" = "cache"
  }
  redshift_subnet_tags = {
    "tier" = "warehouse"
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Private Connectivity Endpoints
# ---------------------------------------------------------------------------

# Gateway endpoint for S3 (free, route-table based)
module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "5.19.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    # Gateway endpoints (free)
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "${local.prefix}s3-endpoint" }
    }

    # Interface endpoints (per-hour + per-GB)
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.prefix}ecr-api-endpoint" }
    }

    ecr_dkr = {
      service             = "ecr.dkr"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.prefix}ecr-dkr-endpoint" }
    }

    ecs = {
      service             = "ecs"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.prefix}ecs-endpoint" }
    }

    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.prefix}ssm-endpoint" }
    }

    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.prefix}ssmmessages-endpoint" }
    }

    ec2messages = {
      service             = "ec2messages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.prefix}ec2messages-endpoint" }
    }

    secretsmanager = {
      service             = "secretsmanager"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "${local.prefix}secretsmanager-endpoint" }
    }
  }

  tags = local.tags
}

# Security group for VPC interface endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.prefix}vpce-"
  vpc_id      = module.vpc.vpc_id
  description = "Allow HTTPS from VPC CIDR to VPC endpoints"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
    description = "HTTPS from VPC"
  }

  tags = merge(local.tags, {
    Name = "${local.prefix}vpce-sg"
  })
}
```

## Outputs (00_network/prod/outputs.tf)

```hcl
# VPC
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC primary CIDR block"
  value       = module.vpc.vpc_cidr_block
}

# Subnets by tier
output "public_subnet_ids" {
  description = "Public subnet IDs (load balancers, NAT)"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs (application workloads)"
  value       = module.vpc.private_subnets
}

output "database_subnet_ids" {
  description = "Database subnet IDs (RDS)"
  value       = module.vpc.database_subnets
}

output "database_subnet_group_name" {
  description = "Database subnet group for RDS instances"
  value       = module.vpc.database_subnet_group_name
}

output "elasticache_subnet_group_name" {
  description = "ElastiCache subnet group for Redis clusters"
  value       = module.vpc.elasticache_subnet_group_name
}

output "redshift_subnet_group_name" {
  description = "Redshift subnet group for warehouse clusters"
  value       = module.vpc.redshift_subnet_group_name
}

# Availability zones
output "azs" {
  description = "Availability zones used"
  value       = module.vpc.azs
}

# NAT
output "nat_public_ips" {
  description = "NAT gateway public IPs (for allowlisting)"
  value       = module.vpc.nat_public_ips
}
```

## Backend Configuration (00_network/prod/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket         = "myorg-prod-tfstate"
    key            = "network"
    region         = "eu-west-1"
    encrypt        = true
    use_lockfile   = true
  }
}
```
