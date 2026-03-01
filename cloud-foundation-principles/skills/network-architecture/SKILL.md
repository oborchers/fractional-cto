---
name: network-architecture
description: "This skill should be used when the user is designing VPC or virtual network topology, planning subnet tiers, configuring NAT gateways, setting up DNS zones, creating private connectivity endpoints, designing API gateway routing, or planning CIDR ranges. Covers subnet tiers (baseline and optional), availability zone distribution, cost-optimized NAT, private service endpoints, DNS strategy, and API gateway patterns."
version: 1.0.0
---

# Design the Network Before the First Compute Resource

Your network is the one thing you cannot change without rebuilding everything on top of it. CIDR ranges, subnet tiers, and availability zone layout are decisions that harden like concrete within days of deploying your first service. A poorly planned network forces painful migrations when you need VPC peering, run out of IP addresses, or discover that your database is in the same subnet as your public load balancer.

Design the network first. Get the CIDR planning, subnet tiers, DNS zones, and private connectivity endpoints right on day one. Everything else -- compute, databases, monitoring -- builds on this foundation.

## Subnet Tiers

Every VPC needs at least three subnet tiers as a baseline. Each tier has its own route table and security posture. Each tier spans multiple availability zones for resilience.

### Baseline: Three Tiers (Every Project)

```
VPC (10.0.0.0/16)
│
├── Public Subnets (/24 x 3 AZs)
│   Purpose: Internet-facing resources only
│   Contains: NAT gateways, load balancers
│   Route: 0.0.0.0/0 -> Internet Gateway
│
├── Private Subnets (/24 x 3 AZs)
│   Purpose: Application workloads
│   Contains: Containers, compute instances, application services
│   Route: 0.0.0.0/0 -> NAT Gateway (outbound only)
│
└── Database Subnets (/24 x 3 AZs)
    Purpose: Managed database engines
    Contains: PostgreSQL, MySQL instances
    Route: No internet access (VPC CIDR only)
```

### Additional Tiers (Add When Needed)

Add dedicated subnet tiers when your architecture requires them. Common additions:

| Tier | Add When | Purpose |
|------|----------|---------|
| Cache | You run managed in-memory stores (Redis, Memcached) | Isolate cache traffic from database traffic; dedicated subnet groups |
| Warehouse | You run analytical databases (data warehouses, columnar stores) | Separate analytical workloads from operational databases |
| Messaging | You run managed message brokers | Isolate broker traffic with dedicated routing |

Reserve CIDR space for future tiers even if you only start with three (see CIDR Planning below).

### Why Separate Subnets?

| Tier | Internet Access | Security Rationale |
|------|----------------|-------------------|
| Public | Full (inbound + outbound) | Only resources that MUST face the internet: load balancers, NAT |
| Private | Outbound only (via NAT) | Application workloads can pull dependencies, but nothing reaches in directly |
| Database | None | Database engines have no reason to touch the internet; reduces attack surface |

Additional tiers (cache, warehouse, messaging) also have no internet access -- they are reachable only from within the VPC.

### Bad vs Good: Subnet Design

```
BAD: Everything in one subnet tier
- All resources share the same route table
- Database instances have outbound internet access
- No network-level isolation between app and data

GOOD: Purpose-specific tiers
- Databases physically cannot reach the internet
- Security groups layer on top of subnet-level isolation
- Managed services get dedicated subnet groups as needed
```

## CIDR Planning

Plan your CIDR ranges to allow future growth, VPC peering, and multi-environment isolation. Overlapping CIDRs between environments make peering impossible.

### Recommended Layout

| Environment | Primary CIDR | Secondary CIDRs | Purpose |
|-------------|-------------|-----------------|---------|
| Development | 10.0.0.0/16 | 10.1.0.0/16, 10.2.0.0/16 | Dev workloads, room for expansion |
| Production | 10.10.0.0/16 | 10.11.0.0/16, 10.12.0.0/16 | Prod workloads, room for expansion |
| Staging | 10.20.0.0/16 | 10.21.0.0/16 | Pre-production validation |
| CI/CD | 10.30.0.0/16 | -- | Build runners, artifact storage |

**Rules**:
- No CIDR overlap between environments (enables future VPC peering)
- No CIDR overlap across regions either -- if you ever need cross-region peering (e.g., eu-west-1 to eu-central-1), colliding CIDRs make it impossible. Plan unique ranges per region from the start.
- /16 gives 65,536 addresses per VPC -- plenty for most startups
- Secondary CIDRs reserved for expansion without re-architecting
- /24 subnets give 251 usable addresses per subnet per AZ -- sufficient for Fargate/ECS workloads. Container-heavy workloads using EKS with VPC CNI (one IP per pod) can exhaust /24 subnets quickly; size up to /22 or /21 for private subnets if running Kubernetes.

### Subnet Addressing Scheme

```
10.0.0.0/16 (Development VPC)
├── Public:     10.0.1.0/24, 10.0.2.0/24, 10.0.3.0/24     (AZ a, b, c)
├── Private:    10.0.11.0/24, 10.0.12.0/24, 10.0.13.0/24   (AZ a, b, c)
├── Database:   10.0.21.0/24, 10.0.22.0/24, 10.0.23.0/24   (AZ a, b, c)
├── Cache:      10.0.31.0/24, 10.0.32.0/24, 10.0.33.0/24   (AZ a, b, c)
└── Warehouse:  10.0.41.0/24, 10.0.42.0/24, 10.0.43.0/24   (AZ a, b, c)
```

The pattern uses the tens digit to encode the tier (1x=private, 2x=database, 3x=cache, 4x=warehouse) and the ones digit to encode the AZ.

## Cost-Optimized NAT Strategy

NAT gateways are expensive. A single NAT gateway costs roughly $32/month plus $0.045/GB of data processed. Multi-AZ NAT (one per AZ) triples this.

### Startup Phase: Single NAT Gateway

```hcl
# Single NAT gateway -- all private subnets route through one
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  enable_nat_gateway = true
  single_nat_gateway = true    # One NAT for cost optimization

  # All private subnets share one NAT
  # Trade-off: if the NAT's AZ goes down, outbound traffic stops
}
```

### Scale Phase: Multi-AZ NAT

```hcl
# One NAT per AZ -- higher cost, full AZ redundancy
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
}
```

**Decision rule**: Start with single NAT. Upgrade to multi-AZ NAT when your monthly NAT bill exceeds $200 or you require AZ-level redundancy for SLA commitments.

## Private Connectivity Endpoints

Private endpoints let your services reach cloud platform APIs without traversing the NAT gateway. This reduces costs (no per-GB NAT charge) and improves security (traffic stays on the cloud provider's backbone network).

### Essential Endpoints

| Endpoint | Why Essential |
|----------|--------------|
| Object Storage (S3) | Container image layers, data lake access, Terraform state |
| Container Registry (ECR/Artifact Registry/ACR) | Image pulls on every deployment |
| Container Orchestration (ECS/Cloud Run) | Task management API calls |
| Session Manager (SSM/IAP) | Operator access without SSH or VPN |
| Secrets Manager | Credential retrieval at container startup |
| Managed Database (RDS) | Database connections stay inside the VPC |

### Gateway vs Interface Endpoints

Some cloud providers distinguish between gateway endpoints (free, route-table based) and interface endpoints (charged, ENI-based). Always use gateway endpoints for high-throughput services like object storage when available.

```hcl
# Gateway endpoint for S3 (free, high throughput)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = module.vpc.private_route_table_ids
  tags = local.tags
}

# Interface endpoint for container registry (per-hour + per-GB charge)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id             = module.vpc.vpc_id
  service_name       = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags = local.tags
}
```

## DNS Architecture

### Zone Strategy

The exact domain structure is up to each company, but a proven starting point is three DNS zones per environment:

| Zone Type | Example | Purpose |
|-----------|---------|---------|
| Public (production) | `myapp.com` | Customer-facing services |
| Public (per-environment) | `dev.myapp.com` | Non-production external access |
| Private (VPC-bound) | `internal` | Service-to-service discovery within VPC |

### Domain Naming Pattern

```
Production:
  api.myapp.com              <- Public API gateway
  app.myapp.com              <- Web application
  *.myapp.com                <- Wildcard for all prod services

Development:
  api.dev.myapp.com          <- Dev API gateway
  *.dev.myapp.com            <- Wildcard for all dev services

Internal (VPC only):
  api.internal               <- Internal API gateway
  cache.internal             <- Redis/cache endpoint
  db.internal                <- Database endpoint (CNAME to managed DB)
```

**Why internal DNS matters**: `db.internal` resolves to the dev database in the dev VPC and to the prod database in the prod VPC. Application code uses the same connection string everywhere -- no environment-specific configuration, no risk of accidentally pointing dev code at a prod database.

### Certificate Strategy

- One wildcard certificate per environment (`*.myapp.com`, `*.dev.myapp.com`)
- Certificates in the primary region for load balancers
- Certificates in the CDN region (often `us-east-1`) for CDN distributions
- DNS-based validation (automated, no manual steps)

## API Gateway Routing

A single API gateway serves as the entry point for all traffic, with clear separation between public and internal routes.

### Public vs Internal Routes

```
Public routes (internet-accessible):
  /api/v1/users              <- User-facing API
  /api/v1/orders             <- Order management
  /webhooks/v1/stripe        <- Third-party webhooks

Internal routes (VPC CIDR restricted):
  /internal/billing/v2/invoices     <- Internal billing service
  /internal/analytics/v1/events     <- Internal event ingestion
  /internal/admin/v1/config         <- Internal admin endpoints
```

**Convention**: The `/internal/` prefix is needed when a single public API gateway serves both external and internal traffic -- the gateway enforces VPC CIDR restriction on all `/internal/` routes, meaning only traffic originating from within the VPC can reach them. For teams that can maintain it, a dedicated internal subdomain (`internal.api.company.com`) on a strictly private load balancer provides stronger separation -- internal routes never share a hostname with public traffic, and the `/internal/` path prefix becomes unnecessary since the entire gateway is private.

### Traffic Flow

```
Internet
  |
Load Balancer (public subnets, HTTPS termination)
  |
API Gateway (private subnets)
  |
  +-- Public routes --> Backend services (private subnets)
  |
  +-- /internal/ routes --> IP restriction (VPC CIDR only)
        |
        Backend services (private subnets)

Private Connectivity Endpoints --> Cloud APIs (no internet traversal)
Session Manager --> Instance access (no SSH keys)
```

## Security Groups

Security groups provide the second layer of network isolation on top of subnet tiers. Define them in the security layer (10_security) and reference them from higher layers.

```
sg_public_http_https     <- Ports 80/443 from 0.0.0.0/0 (load balancers only)
sg_private_base          <- Default deny-all ingress (baseline for all private resources)
sg_private_postgres      <- Port 5432 from VPC CIDR (managed databases)
sg_private_redis         <- Port 6379 from VPC CIDR (cache clusters)
sg_private_app           <- Port 8080 from VPC CIDR + self (application containers)
sg_private_warehouse     <- Port 5439 from VPC CIDR (data warehouse)
```

**Pattern**: `sg_private_*` groups allow traffic only from within the VPC CIDR. `sg_public_*` groups are assigned exclusively to internet-facing resources like load balancers.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Virtual network | VPC | VPC | Virtual Network (VNet) |
| Subnet with route table | Subnet + Route Table | Subnet (routes on VPC) | Subnet + Route Table |
| Internet gateway | Internet Gateway | Default internet route | Internet routing (default) |
| NAT for outbound traffic | NAT Gateway | Cloud NAT | NAT Gateway |
| Private service connectivity | VPC Endpoints (PrivateLink) | Private Service Connect | Private Endpoints |
| DNS management | Route53 | Cloud DNS | Azure DNS |
| Certificate management | ACM | Certificate Manager | Key Vault Certificates |
| Load balancer | ALB / NLB | Cloud Load Balancing | Application Gateway |
| CDN | CloudFront | Cloud CDN | Front Door |
| Web application firewall | AWS WAF | Cloud Armor | Azure WAF |
| Session-based instance access | SSM Session Manager | IAP Tunneling | Azure Bastion |
| Network security rules | Security Groups | Firewall Rules | Network Security Groups |

## Examples

Working implementations in `examples/`:
- **`examples/vpc-with-tiers.md`** -- Complete VPC with baseline subnet tiers, CIDR planning, NAT gateway, and private connectivity endpoints
- **`examples/dns-and-certificates.md`** -- DNS zone setup with public, per-environment, and private zones plus wildcard certificates

## Review Checklist

When designing or reviewing network architecture:

- [ ] CIDR ranges are planned to avoid overlap between environments (enables future peering)
- [ ] At least three subnet tiers exist: public, private, database (add cache, warehouse, messaging as needed)
- [ ] Subnets span at least 3 availability zones
- [ ] Database subnets (and any additional data tiers) have no internet route
- [ ] NAT gateway strategy is documented (single for cost, multi-AZ for resilience)
- [ ] Private connectivity endpoints exist for high-traffic cloud APIs (storage, registry, secrets)
- [ ] Public DNS zone, per-environment DNS zone, and private VPC-bound DNS zone are configured
- [ ] Wildcard certificates cover each environment
- [ ] API gateway clearly separates public and internal routes (`/internal/` prefix or dedicated internal subdomain)
- [ ] Internal routes enforce VPC CIDR restriction
- [ ] Security groups follow the `sg_private_*` / `sg_public_*` naming convention
- [ ] Only load balancers are in public subnets; everything else is in private or data subnets
- [ ] Secondary CIDRs are reserved for future expansion
- [ ] CIDR ranges do not overlap across regions (enables future cross-region peering)
- [ ] Private subnet sizing accounts for container IP consumption (EKS with VPC CNI may need /22 or /21)
