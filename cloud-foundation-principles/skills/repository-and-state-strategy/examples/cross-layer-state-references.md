# Cross-Layer State References

Demonstrates how higher-numbered infrastructure layers consume outputs from lower-numbered layers via `terraform_remote_state`. This pattern creates explicit, auditable dependency chains without hardcoding values.

## Dependency Graph

```
00_network  ---->  10_security  ---->  30_databases
    |                  |                    |
    |                  |                    v
    +------------------+------------->  40_compute
                       |                    |
                       v                    v
                   50_edge       60_messaging --> 70_monitoring
```

Arrows indicate "reads from." Layer 40 (compute) reads outputs from both layer 00 (network) and layer 10 (security).

## Network Layer: Defines and Exports

### 00_network/dev/vpc.tf

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "${local.prefix}vpc"
  cidr = "10.0.0.0/16"

  azs              = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  database_subnets = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true  # Cost optimization: one NAT per env
  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group = true

  tags = local.tags
}
```

### 00_network/dev/outputs.tf

```hcl
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "public_subnets" {
  value = module.vpc.public_subnets
}

output "database_subnet_group_name" {
  value = module.vpc.database_subnet_group_name
}

output "dns_zone_id" {
  value = aws_route53_zone.public.zone_id
}

output "internal_dns_zone_id" {
  value = aws_route53_zone.internal.zone_id
}
```

## Security Layer: Reads Network, Defines and Exports

### 10_security/dev/main.tf

```hcl
module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "platform"
  env         = "dev"
  name        = "security"
  cost_center = "infrastructure"
  scope       = "g"
}

# Read network layer outputs
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "network"
    region = "eu-west-1"
  }
}

locals {
  tags   = module.labels.tags
  prefix = module.labels.prefix
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
}
```

### 10_security/dev/security_groups.tf

```hcl
resource "aws_security_group" "private_base" {
  name_prefix = "${local.prefix}private-base-"
  vpc_id      = local.vpc_id
  description = "Base security group for all private resources"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow all traffic within the security group"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = local.tags
}

resource "aws_security_group" "postgres" {
  name_prefix = "${local.prefix}postgres-"
  vpc_id      = local.vpc_id
  description = "Allow PostgreSQL traffic"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.private_base.id]
    description     = "PostgreSQL from private base SG"
  }

  tags = local.tags
}

resource "aws_security_group" "redis" {
  name_prefix = "${local.prefix}redis-"
  vpc_id      = local.vpc_id
  description = "Allow Redis traffic"

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.private_base.id]
    description     = "Redis from private base SG"
  }

  tags = local.tags
}
```

### 10_security/dev/outputs.tf

```hcl
output "base_security_group_ids" {
  value = [aws_security_group.private_base.id]
}

output "postgres_security_group_id" {
  value = aws_security_group.postgres.id
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}

output "wildcard_certificate_arn" {
  value = aws_acm_certificate.wildcard.arn
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}
```

## Compute Layer: Reads Network + Security

### 40_compute/dev/main.tf

```hcl
module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "platform"
  env         = "dev"
  name        = "compute"
  cost_center = "infrastructure"
  scope       = "g"
}

# Read from network layer
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "network"
    region = "eu-west-1"
  }
}

# Read from security layer
data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = "myorg-dev-tfstate"
    key    = "security"
    region = "eu-west-1"
  }
}

locals {
  tags            = module.labels.tags
  prefix          = module.labels.prefix
  vpc_id          = data.terraform_remote_state.network.outputs.vpc_id
  private_subnets = data.terraform_remote_state.network.outputs.private_subnets
  base_sg_ids     = data.terraform_remote_state.security.outputs.base_security_group_ids
}
```

### 40_compute/dev/cluster.tf

```hcl
module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 5.0"

  cluster_name = "${local.prefix}cluster"

  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 50
        base   = 1
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 50
      }
    }
  }

  tags = local.tags
}
```

### 40_compute/dev/outputs.tf

```hcl
output "ecs_cluster_arn" {
  description = "ECS cluster ARN for service deployment"
  value       = module.ecs_cluster.arn
}

output "ecs_cluster_name" {
  description = "ECS cluster name for CloudWatch metrics"
  value       = module.ecs_cluster.name
}
```

## Database Layer: Reads Network + Security

### 30_databases/dev/main.tf

```hcl
module "labels" {
  source      = "git::https://github.com/myorg/tf-module-labels.git?ref=v1.2.0"
  team        = "platform"
  env         = "dev"
  name        = "databases"
  cost_center = "data"
  scope       = "g"
}

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

locals {
  tags               = module.labels.tags
  prefix             = module.labels.prefix
  db_subnet_group    = data.terraform_remote_state.network.outputs.database_subnet_group_name
  postgres_sg_id     = data.terraform_remote_state.security.outputs.postgres_security_group_id
  redis_sg_id        = data.terraform_remote_state.security.outputs.redis_security_group_id
  kms_key_arn        = data.terraform_remote_state.security.outputs.kms_key_arn
}
```

## Anti-Pattern: Hardcoded Cross-Layer Values

```hcl
# BAD: Hardcoded values instead of remote state references
locals {
  vpc_id          = "vpc-0a1b2c3d4e5f67890"  # What if this changes?
  private_subnets = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  cluster_arn     = "arn:aws:ecs:eu-west-1:123456789012:cluster/my-cluster"
}
```

This breaks the moment any lower layer changes. Remote state references always return the current value.

## Key Points

- Dependencies flow in one direction: higher-numbered layers read from lower-numbered layers
- Each layer declares its remote state dependencies explicitly at the top of `main.tf`
- Output definitions in lower layers form a contract -- changing them is a breaking change for consumers
- Local variables alias remote state outputs for readability throughout the layer
- Never hardcode values that come from another layer -- always use `terraform_remote_state`
- The remote state pattern works identically across all cloud provider backends (S3, GCS, Azure Blob)
