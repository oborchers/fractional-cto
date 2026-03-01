---
name: managed-services-over-self-hosted
description: "This skill should be used when the user is choosing between managed and self-hosted services, deciding whether to run Kubernetes or use managed containers, evaluating self-hosted databases vs managed databases, considering self-hosted monitoring or caches, designing for a small team (under 50 engineers), or justifying a self-hosted exception. Covers the operations tax of self-hosting, managed container orchestration over Kubernetes for small teams, managed workflow engines, managed caches and databases, managed monitoring, and the decision framework for when self-hosting is genuinely justified."
version: 1.0.0
---

# Every Self-Hosted Service Is a Person You Didn't Hire

Self-hosting a database, a cache, a workflow engine, or a Kubernetes cluster is not free. It costs patching, backup verification, incident response at 3 AM, capacity planning, version upgrades, security hardening, and monitoring of the monitor. Each self-hosted service is an invisible full-time job. For a team of five engineers shipping a SaaS product, running your own PostgreSQL is the equivalent of hiring a sixth engineer whose entire job is keeping PostgreSQL alive -- except you do not hire that person, so the work falls on everyone, and nobody does it well.

Managed services trade money for engineering time. For startups and small teams (under 50 engineers), this trade is almost always correct. The cloud bill goes up by hundreds of dollars per month; the engineering team gets back thousands of dollars in reclaimed time. Self-host only when the managed service genuinely cannot meet your requirements -- and document the justification in an ADR.

## The Operations Tax

Every self-hosted service carries a recurring operations cost that is invisible until something breaks.

| Operations Task | Managed Service | Self-Hosted |
|-----------------|-----------------|-------------|
| OS/kernel patching | Provider handles it | You schedule downtime, test, apply |
| Version upgrades | One-click or automatic | You test, migrate, rollback-plan, execute |
| Backup & restore | Automated, point-in-time | You configure, verify, test restores quarterly |
| Scaling | Auto-scaling or single API call | You monitor, forecast, provision, rebalance |
| High availability | Built-in multi-AZ/region | You design, implement, test failover |
| Security hardening | Provider hardens, you configure | You harden OS, network, application, and runtime |
| Monitoring | Built-in metrics and logs | You deploy exporters, configure dashboards, set alerts |
| Incident response | Provider's SRE team + your config | Your team, 24/7, for infrastructure AND application |
| Compliance | Provider certifications (SOC2, HIPAA) | You certify the infrastructure yourself |

**The compound effect:** one self-hosted service is manageable. Three self-hosted services (database + cache + monitoring stack) consume 30-50% of a small team's operational capacity. Five self-hosted services and you are an infrastructure company that happens to also build a product.

## Container Orchestration: Managed Over Kubernetes

Kubernetes is the most frequently self-hosted service that teams do not need. For teams under 50 engineers running fewer than 20 services, managed container platforms provide the same deployment model (containers, health checks, scaling, load balancing) without the operational overhead of cluster management, node pool sizing, ingress controller configuration, CNI plugin selection, and etcd maintenance.

### Decision Framework

| Criterion | Use Managed Containers | Use Kubernetes |
|-----------|----------------------|----------------|
| Team size | Under 50 engineers | 50+ engineers with dedicated platform team |
| Service count | Under 20 services | 20+ services with complex networking |
| GPU workloads | No, or minimal | Heavy GPU scheduling requirements |
| Custom scheduling | Not needed | Custom schedulers, operators, CRDs required |
| Multi-cloud | Not required | Required for portability |
| Service mesh | Not needed | Istio/Linkerd required |
| Compliance | Standard | Requires specific K8s-level audit controls |

### Good Pattern vs Bad Pattern

```hcl
# Good: managed container service for a team of 8 engineers

resource "aws_ecs_service" "myapp" {
  name            = "myapp"
  cluster         = data.terraform_remote_state.compute.outputs.cluster_arn
  task_definition = aws_ecs_task_definition.myapp.arn
  desired_count   = 2

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 50  # Increase to 100 for production-critical services
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 50  # Spot can be interrupted; suitable for dev, use cautiously in prod
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Zero-downtime rolling update
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
}

# Result: no nodes to patch, no cluster upgrades, no CNI plugins,
# no ingress controllers, no etcd backups. Deploy and forget.
```

```hcl
# Bad: self-managed Kubernetes for the same team of 8

resource "aws_eks_cluster" "main" {
  name     = "myapp-cluster"
  role_arn = aws_iam_role.eks.arn
  version  = "1.28"  # You must upgrade this every 3-4 months

  vpc_config {
    subnet_ids = var.private_subnet_ids
  }
}

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workers"
  instance_types  = ["m5.large"]
  scaling_config {
    desired_size = 3
    max_size     = 6
    min_size     = 2
  }
  # Now you also need: ingress-nginx, cert-manager, external-dns,
  # metrics-server, cluster-autoscaler, aws-load-balancer-controller,
  # and someone to upgrade all of them every quarter.
}
```

## Workflow Orchestration: Managed Over Self-Hosted

Self-hosted workflow engines (Airflow on EC2/K8s, Temporal self-hosted, Prefect server) require database backends, worker scaling, scheduler high availability, log aggregation, and web UI hosting. Managed workflow services handle all of this.

| Approach | What You Manage | What the Provider Manages |
|----------|-----------------|---------------------------|
| Managed Airflow | DAG code, connections, variables | Scheduler HA, worker scaling, web UI, database, upgrades |
| Self-hosted Airflow | DAG code, connections, variables, scheduler HA, worker scaling, web UI, metadata DB, Redis/Celery, upgrades, monitoring | Nothing |
| Managed step functions | Workflow definitions | Execution, scaling, retry, logging, state persistence |
| Self-hosted Temporal | Workflow code, namespace management, history DB, visibility DB, upgrades, monitoring | Nothing |

**The breaking point:** self-hosted Airflow is three services (scheduler, webserver, workers), a metadata database, a message broker, and a log storage backend. That is six components to keep alive for a workflow engine that is supposed to keep your other workflows alive.

**Do your research first:** managed workflow services vary significantly in quality. Sometimes your cloud provider's offering (e.g., MWAA) is the right choice; sometimes a specialized third-party provider (e.g., Astronomer for Airflow) offers a materially better experience. Evaluate both before committing.

## Databases and Caches: Always Managed

There is almost no scenario where a startup or small team should run a self-hosted database or cache in production. The managed service gives you automated backups, point-in-time recovery, failover, patching, and monitoring for a modest premium over the raw compute cost.

```hcl
# Good: managed database with automated operations

resource "aws_db_instance" "myapp" {
  identifier     = "${module.labels.prefix}myapp-db"
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t4g.medium"

  multi_az                    = true     # Automatic failover
  backup_retention_period     = 14       # 14-day point-in-time recovery
  auto_minor_version_upgrade  = true     # Security patches applied automatically
  storage_encrypted           = true
  performance_insights_enabled = true    # Built-in query monitoring
  deletion_protection         = true
}
```

```hcl
# Bad: self-hosted PostgreSQL on an EC2 instance

resource "aws_instance" "postgres" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "m5.large"

  # Now you must:
  # - Install and configure PostgreSQL
  # - Set up streaming replication for HA
  # - Configure automated backups to object storage
  # - Test backup restores quarterly
  # - Apply OS security patches monthly
  # - Apply PostgreSQL patches on your schedule
  # - Monitor replication lag, connections, disk, memory
  # - Handle failover manually or build automation
  # - Manage SSL certificates for connections
  # - None of this is in the Terraform above
}
```

**The same logic applies to caches.** A managed Redis/Valkey instance with automatic failover, patching, and backup costs marginally more than the equivalent EC2 instance and saves dozens of hours per quarter in operational toil.

## Monitoring: Managed Over Self-Hosted

Self-hosted monitoring stacks (Prometheus + Grafana + Alertmanager + Loki) are four services that each need their own storage, scaling, and high availability. When your monitoring is down, you are blind to everything else being down. Managed monitoring services eliminate this circular dependency.

| Component | Self-Hosted | Managed Alternative |
|-----------|-------------|---------------------|
| Metrics collection | Prometheus (+ storage, HA, federation) | Managed Prometheus / cloud metrics |
| Visualization | Grafana (+ database, auth, HA) | Managed Grafana / cloud dashboards |
| Alerting | Alertmanager (+ dedup, routing, HA) | Cloud alerting / managed alert rules |
| Log aggregation | Loki or ELK (+ storage, retention, indexing) | Cloud logging service |

**The irony of self-hosted monitoring:** the one service that must be available when everything else is failing is the one you built yourself on the same infrastructure that is failing. Managed monitoring runs on the provider's infrastructure, independent of your workloads.

## The Only Valid Exceptions

Self-hosting is justified when -- and only when -- the managed service genuinely cannot meet a hard requirement. Document every exception in an ADR with this structure:

1. **What managed service was evaluated?**
2. **What specific requirement does it fail to meet?** (Not "it's expensive" -- quantify the cost difference.)
3. **What is the operations plan?** (Who patches? Who handles incidents? What is the backup/restore process?)
4. **What is the exit criteria?** (When the managed service adds this capability, we migrate back.)

### Legitimate exceptions (rare)

- **GPU workloads requiring specific scheduling** -- managed containers may not support fractional GPU allocation or custom device plugins. Self-managed nodes with a managed control plane is the compromise.
- **Regulatory data residency** -- the managed service is not available in the required region. Document which region and check quarterly.
- **Extreme performance requirements** -- the managed service adds latency that violates SLAs. Prove it with benchmarks, not assumptions.

### Not legitimate exceptions

- "It's cheaper to self-host" -- it is not, once you account for engineering time.
- "We need more control" -- control over what, specifically? If you cannot name the exact configuration, you do not need it.
- "We already know how to run it" -- knowing how to run PostgreSQL does not mean your team should spend time running it instead of building product features.

## The Decision Rule

**If your platform team would not accept the operational burden of maintaining it, do not self-host it.** Use the managed service -- that is the paved road. Self-hosted Kubernetes needs a dedicated platform engineer. Self-hosted monitoring needs an observability engineer. If those roles do not exist on your team, the managed equivalent is the correct choice.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Managed containers (standard) | ECS Fargate | Cloud Run / GKE Autopilot | Container Apps |
| Managed containers (GPU) | ECS with EC2 capacity providers | GKE with GPU node pools | AKS with GPU node pools |
| Managed Kubernetes | EKS (if you must) | GKE Autopilot | AKS |
| Managed PostgreSQL | RDS PostgreSQL / Aurora | Cloud SQL / AlloyDB | Azure Database for PostgreSQL |
| Managed Redis/cache | ElastiCache / MemoryDB | Memorystore | Azure Cache for Redis |
| Managed workflow engine | MWAA (Airflow) / Step Functions | Cloud Composer / Workflows | (no direct Airflow equivalent) / Logic Apps |
| Managed Prometheus | Amazon Managed Prometheus | Cloud Monitoring (built-in) | Azure Monitor (Prometheus) |
| Managed Grafana | Amazon Managed Grafana | Cloud Monitoring dashboards | Azure Managed Grafana |
| Managed log aggregation | CloudWatch Logs | Cloud Logging | Azure Monitor Logs |

## Examples

Working implementations in `examples/`:
- **`examples/managed-container-service.md`** -- Complete managed container deployment with spot/preemptible capacity, circuit breaker rollback, auto-scaling, and zero-downtime rolling updates -- no cluster management required
- **`examples/managed-data-stack.md`** -- Production-grade managed database and cache with automated backups, failover, encryption, and monitoring -- contrasted against the self-hosted equivalent to illustrate the operations tax

## Review Checklist

When designing or reviewing service hosting decisions:

- [ ] Every self-hosted service has a written ADR justifying why the managed alternative was rejected
- [ ] Container orchestration uses a managed service (ECS, Cloud Run, Container Apps), not self-managed Kubernetes, unless team size exceeds 50 engineers or GPU scheduling requires it
- [ ] Databases are managed services with automated backups, failover, and patching
- [ ] Caches are managed services, not self-hosted Redis/Memcached on EC2/GCE
- [ ] Workflow orchestration uses a managed service, not self-hosted Airflow/Temporal
- [ ] Monitoring uses managed services -- self-hosted monitoring that fails alongside your infrastructure is worse than no monitoring
- [ ] No self-hosted service exists solely because "it's cheaper" without accounting for engineering time
- [ ] Self-hosted exceptions include an operations plan (patching, backup, incident response) and exit criteria
- [ ] GPU workloads use managed control planes with self-managed node pools, not fully self-managed clusters
- [ ] The platform team accepts the operational burden for each self-hosted service -- if not, it should be managed
