---
name: secrets-and-configuration-management
description: "This skill should be used when the user is storing credentials, managing API keys, setting up secret rotation, designing secret naming conventions, creating database users, managing environment-specific configuration, or deciding how applications should access secrets at runtime. Covers the one-secret-per-service pattern, account-based environment isolation, KMS encryption, role-based database users, and the infrastructure wiring exception for parameter stores."
version: 1.0.0
---

# One Secret Per Service, One Path Everywhere

The most common infrastructure mistake with credentials is over-engineering the separation. Splitting database passwords into a secrets manager, endpoints into a parameter store, and feature flags into environment variables creates three access patterns, three IAM policies, and a Terraform apply every time you change a connection string.

Put everything in one secret per service. One JSON blob containing every environment variable the service needs -- credentials, endpoints, flags, all of it. Store it in a secrets manager with customer-managed encryption. The application reads and parses the secret at startup. Done.

## Core Principles

1. **One secret per service.** Each service has exactly one secret: `/{service}/env`. It contains a JSON object with every env var the service needs -- database passwords next to database hosts, API keys next to feature flags. No separation between "secrets" and "configuration."

2. **Account = environment.** The secret path is `/{service}/env` in every account. Dev account, prod account, staging account -- same path. The AWS account provides the isolation (see `multi-account-from-day-one` skill). Application code never needs to know which environment it runs in. This mirrors the internal DNS pattern (see `network-architecture` skill) where `db.internal` resolves to the right database per VPC -- same hostname everywhere, different values per environment.

3. **Change without Terraform.** Update the secret value in the console or CLI, force a container redeploy. No plan/apply cycle for config changes. Terraform creates the secret resource and sets the initial value; the team manages the value thereafter.

4. **Customer-managed encryption.** Every secret is encrypted with a KMS key you control, not the provider default. This enables key rotation, cross-account access policies, and decryption audit trails.

5. **Rotation is a spectrum.** Database credentials can auto-rotate if you invest in the rotation Lambda. Third-party API keys (Stripe, SendGrid) rarely rotate in practice. Don't let perfect rotation block shipping. Start with KMS encryption and proper access scoping; add rotation when it matters.

### The Secret Blob

```json
{
  "DB_HOST": "mydb.cluster-xxx.eu-west-1.rds.amazonaws.com",
  "DB_PORT": "5432",
  "DB_PASSWORD": "auto-rotated-or-manual",
  "REDIS_URL": "redis://cache.internal:6379",
  "SENDGRID_API_KEY": "SG.xxx",
  "FEATURE_V2_API": "true"
}
```

One JSON object. One secret ARN. One IAM policy statement. The application reads `/{service}/env` at startup, parses the JSON, and populates its environment.

### Good Pattern vs Bad Pattern

```hcl
# Good: one secret, app reads and parses at startup

resource "aws_secretsmanager_secret" "env" {
  name       = "/${var.service_name}/env"
  kms_key_id = aws_kms_key.secrets.arn
}

resource "aws_ecs_task_definition" "myapp" {
  # ...
  container_definitions = jsonencode([{
    name = var.service_name
    environment = [{
      name  = "SECRET_NAME"
      value = "/${var.service_name}/env"
    }]
  }])
}
```

```hcl
# Bad: plaintext password in environment variable via Terraform

resource "aws_ecs_task_definition" "myapp" {
  container_definitions = jsonencode([{
    name = "myapp"
    environment = [{
      name  = "DB_PASSWORD"
      value = "hunter2"  # Plaintext in state file, logs, and console
    }]
  }])
}
```

```
# Bad: separate stores for secrets and configuration

/prod/myapp/db-password      --> Secrets Manager
/prod/myapp/db-host          --> SSM Parameter Store
/prod/myapp/redis-url        --> SSM Parameter Store
/prod/myapp/sendgrid-api-key --> Secrets Manager

# Two stores, two access patterns, two IAM policies,
# and a Terraform apply to change a connection string.
```

## Naming Convention: /{service}/env

```
Dev account (123456789012):
  /myapp/env                 (all env vars for myapp)
  /myapp/db-app_rw           (database role credential)
  /myapp/db-analytics_ro     (database role credential)

Prod account (987654321098):
  /myapp/env                 (all env vars for myapp)
  /myapp/db-app_rw           (database role credential)
  /myapp/db-analytics_ro     (database role credential)
```

Same paths. Same code. Different accounts. Application code reads `/{service}/env` -- it never needs to know whether it runs in dev or prod.

**Database role credentials** are the exception to the one-blob rule. They are stored as individual secrets at `/{service}/db-{role}` because they are shared across consumers (app service, analytics service, RDS proxy) and auto-rotation targets individual secrets, not keys inside a blob.

## When to Use Parameter Store

The one-secret-per-service pattern covers everything an application needs at runtime. But cross-service infrastructure dependencies -- where one Terraform module's output feeds another module's input -- need a different mechanism.

**Use SSM Parameter Store (or Terraform remote state) for infrastructure wiring:**

- A database endpoint that changes when the RDS instance is replaced
- A VPC ID or subnet ID consumed by multiple modules
- A load balancer DNS name that other services route to

These values change when infrastructure changes. They must flow through Terraform or a parameter store so dependent modules pick up the new value automatically. They are not application config -- they are infrastructure bindings.

```hcl
# Infrastructure wiring: consumed by Terraform modules, not application code
resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/${var.service_name}/infra/db-endpoint"
  type  = "String"
  value = aws_db_instance.main.address

  tags = local.tags
}
```

## Database Users: Role-Based, Never Person-Specific

Database users follow the same principle. Never create person-specific database accounts (`john_doe`, `jane_smith`). Create role-based users that describe purpose and access level.

### Role Naming Convention: {purpose}_{access}

Use abbreviated access suffixes for brevity (see `naming-and-labeling-as-code` skill for the canonical naming conventions):

```
api_rw            -- API service (read + write)
api_ro            -- API service (read only, e.g., replica queries)
dashboard_ro      -- Analytics/BI tools (read only, all tables)
migration_admin   -- Schema migration runner (DDL permissions, time-boxed)
generic_ro        -- All team members (read only, for debugging)
```

### Access Model

```
Individual developer access:
  Developer --> SSO --> Cloud console --> Database proxy --> generic_ro role
  (No personal credentials. Access revoked by disabling SSO account.)

Application access:
  Container --> Reads /{service}/env --> Gets DB_PASSWORD --> Connects directly
  (Password from secrets manager. No human knows the password.)

Analytics access:
  BI tool --> Reads /{service}/db-analytics_ro --> Connects via proxy
  (Scoped to SELECT on reporting tables only.)

Emergency admin access:
  SRE --> SSO --> Temporary admin session --> migration_admin role
  (Time-boxed to 1 hour. Fully audited. Requires approval.)
```

### Why No Personal Database Users

- **Offboarding is instant.** Disable the SSO account, and all access revokes. No need to find and delete database users across dozens of instances.
- **Credential sprawl is eliminated.** Ten developers do not mean ten passwords to manage, rotate, and audit.
- **Audit trails are cleaner.** Actions are traceable to SSO identity through the cloud provider's audit log, not to a database username that might be shared.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Secrets storage | Secrets Manager | Secret Manager | Key Vault |
| Encryption keys | KMS (customer-managed CMK) | Cloud KMS | Key Vault (keys) |
| Auto-rotation | Rotation Lambdas | Rotation via Cloud Functions | Key Vault rotation policies |
| Infrastructure config (cross-service wiring) | SSM Parameter Store | Secret Manager labels or Firestore | App Configuration |
| Database proxy | RDS Proxy / IAM DB auth | Cloud SQL Auth Proxy | Microsoft Entra ID DB auth |
| Credential-free CLI | `aws sso login` | `gcloud auth login` | `az login` |

## Examples

Working implementations in `examples/`:
- **`examples/secrets-and-config-separation.md`** -- Complete single-secret-per-service setup with KMS encryption, one JSON blob, ECS task definition, and scoped IAM policies
- **`examples/database-role-management.md`** -- Role-based database user creation with purpose-named roles, individual secrets per role, and IAM-based developer access through a database proxy

## Review Checklist

When designing or reviewing secrets and configuration management:

- [ ] Every service has one secret: `/{service}/env` containing a JSON blob with all env vars
- [ ] Secret paths have no environment prefix (account = environment isolation)
- [ ] Same secret path works identically in dev and prod accounts
- [ ] All secrets encrypted with customer-managed KMS keys, not provider defaults
- [ ] Application reads and parses the secret at startup (no ECS secrets block injection)
- [ ] IAM policies scope secret access to the task role, not the execution role
- [ ] Database credentials are individual secrets at `/{service}/db-{role}` (exception to one-blob rule)
- [ ] Database users are role-based (`{purpose}_{access}`), not person-specific
- [ ] Developer database access uses SSO + database proxy with a shared read-only role
- [ ] Cross-service infrastructure dependencies flow through Terraform outputs or SSM Parameter Store
- [ ] No secrets exist in Terraform outputs, environment variable literals, or committed `.env` files
- [ ] Third-party API keys that cannot auto-rotate are documented with rotation schedule
- [ ] Config changes are deployable without Terraform apply (update secret + force redeploy)
