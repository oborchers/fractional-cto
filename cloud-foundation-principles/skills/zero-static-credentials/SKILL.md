---
name: zero-static-credentials
description: "This skill should be used when the user is configuring SSO, setting up CI/CD authentication, designing OIDC federation, eliminating SSH keys or VPN, managing human or machine identity, or discussing credential lifecycle. Covers core access patterns (human SSO, pipeline OIDC, operator session-based), federated identity, workload identity federation, and the elimination of static API keys, SSH keys, and VPN files."
version: 1.0.0
---

# No .pem Files, No .ovpn Files, No Long-Lived API Keys

Static credentials are the number one cause of cloud security breaches. An SSH key on a developer's laptop, a VPN configuration file shared via Slack, cloud provider access keys stored in a CI/CD secret -- each one is a ticking time bomb. Static credentials cannot be revoked instantly across all consumers. They accumulate silently over time. They are almost always over-permissioned. And when they leak (not if), the blast radius is unknowable because nobody tracks where they were copied.

Zero static credentials applies fully to **cloud provider credentials** -- no long-lived AWS access keys, no GCP service account key files, no SSH key pairs, no VPN configuration files. Every cloud access path uses short-lived, automatically rotated, centrally revocable tokens. Three core access patterns cover the vast majority of cloud interactions.

**Third-party service credentials** (Supabase keys, Stripe API keys, NPM tokens, SendGrid keys) are a different category. Most third-party services do not support OIDC or workload identity federation, so these credentials must be stored somewhere. CI/CD secret stores and cloud secrets managers are the correct places -- they are encrypted, access-controlled, and auditable. For these credentials, the goal is not elimination but proper management: store in an encrypted secret store, scope to minimum permissions, and rotate on a schedule where the service supports it.

## The Core Access Patterns

These three patterns cover human access, automated pipelines, and operational debugging. If a proposed access method does not use short-lived, centrally revocable tokens, it is a security liability.

| Pattern | Who | How | Token Lifetime |
|---------|-----|-----|----------------|
| Human -> SSO -> Cloud | Developers, operators, admins | Federated identity (SSO) to cloud console and CLI | 1-12 hours (session) |
| Pipeline -> OIDC -> Cloud | CI/CD workflows, automated deploys | Workload identity federation (OIDC) | Minutes (per-job) |
| Operator -> Session Manager -> Instance | On-call engineers, debuggers | Session-based instance access (no SSH) | Duration of session |

### What Each Pattern Eliminates

| Eliminated | Replaced By | Why It Matters |
|-----------|-------------|----------------|
| IAM access keys (API key + secret) | SSO temporary credentials | Access keys are permanent until manually rotated; SSO tokens expire automatically |
| SSH key pairs (.pem files) | Session-based instance access | SSH keys are copied, shared, never rotated, and impossible to audit |
| VPN configuration (.ovpn files) | Private connectivity endpoints + session manager | VPN files are shared, credentials embedded, and revocation requires redistribution |
| Stored CI/CD secrets (cloud credentials) | OIDC federation | CI/CD secrets are long-lived, often over-permissioned, and shared across pipelines |
| Database passwords in developer machines | Team-based roles + IAM authentication | Individual credentials create sprawl; IAM auth uses SSO session |

## Pattern 1: Human Access via SSO

Every human accesses the cloud through a single sign-on provider. When an employee leaves, disabling their SSO account instantly revokes all cloud access across all accounts and services.

### Architecture

```
External Identity Provider (Google Workspace, Okta, Entra ID)
    |
    | SAML / OIDC federation
    |
Cloud Identity Service (IAM Identity Center, Cloud Identity, Entra ID)
    |
    +-- Permission Set: Admin     -> Full access (2-3 people)
    +-- Permission Set: Developer -> Full dev, read-only prod
    +-- Permission Set: ReadOnly  -> Audit and compliance
    |
    +-- Account: dev         -> Developer: full access
    +-- Account: prod        -> Developer: read-only (targeted exceptions)
    +-- Account: sandbox     -> Developer: full access
    +-- Account: security    -> Admin only
```

### Key Design Decisions

**External IdP as single source of truth**: Do not manage users in the cloud provider. Your identity provider (Google Workspace, Okta, Microsoft Entra ID) is the single source of truth. Onboarding means adding a user to the IdP. Offboarding means disabling the IdP account. No second step required.

**Three permission tiers** (Admin, Developer, ReadOnly): See the `multi-account-from-day-one` skill for the full tier definitions and per-account access scoping.

**MFA enforced at the IdP**: Multi-factor authentication is configured in the identity provider, not in the cloud. This ensures MFA covers all access paths, not just the cloud console.

### Bad vs Good: Human Access

```
BAD: Static credentials for human access
- Developer has AWS_ACCESS_KEY_ID in ~/.aws/credentials
- Key was created 18 months ago, never rotated
- Key has AdministratorAccess (over-permissioned)
- Developer left the company 3 months ago (key still active)
- Nobody knows this key exists

GOOD: SSO-based access
- Developer authenticates via Google Workspace SSO
- Session token expires in 8 hours
- Access scoped to DeveloperAccess permission set
- Developer leaves -> Google account disabled -> instant cloud revocation
- All sessions auditable via IdP logs
```

## Pattern 2: CI/CD Access via OIDC Federation

CI/CD pipelines authenticate to the cloud using workload identity federation (OIDC). The CI/CD platform (GitHub Actions, GitLab CI, etc.) provides a signed JWT token. The cloud provider validates the token and issues short-lived credentials scoped to a specific role. No secrets are stored anywhere.

### Architecture

```
CI/CD Platform (GitHub Actions, GitLab CI, etc.)
    |
    | Signed JWT (OIDC token)
    | Claims: repo, branch, workflow, environment
    |
Cloud Provider OIDC Trust
    |
    | Validates token signature + claims
    | Issues short-lived credentials (minutes)
    |
    +-- Role: InfraDeployRole  -> Terraform apply permissions
    +-- Role: AppDeployRole    -> Container push + service update
    +-- Role: ReadOnlyRole     -> Terraform plan only (PRs)
```

### Trust Policy Configuration

The OIDC trust policy controls exactly which repositories and branches can assume which roles. This is the critical security boundary.

```hcl
# OIDC provider (created once per account)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Role assumable ONLY by specific repositories
resource "aws_iam_role" "github_actions" {
  name = "GithubActionsDeployRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:myorg/infrastructure:*",
              "repo:myorg/api-service:*"
            ]
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}
```

### CI/CD Workflow Usage

```yaml
# .github/workflows/deploy.yml
name: Deploy Infrastructure
on:
  push:
    tags: ["v*"]

permissions:
  id-token: write    # Required for OIDC
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Authenticate via OIDC -- no stored secrets
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsDeployRole
          aws-region: eu-west-1
          # No access key, no secret key -- OIDC only

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - run: terraform init
      - run: terraform apply -auto-approve
```

### Bad vs Good: CI/CD Authentication

```
BAD: Static credentials in CI/CD
- AWS_ACCESS_KEY_ID stored as GitHub secret
- AWS_SECRET_ACCESS_KEY stored as GitHub secret
- Keys have AdministratorAccess
- Keys were created 2 years ago
- Same keys used across 15 repositories
- Cannot revoke without breaking all pipelines

GOOD: OIDC federation for cloud credentials
- No cloud credentials stored in CI/CD platform
- Each job gets unique, short-lived cloud credentials
- Role assumption restricted to specific repositories
- Token expires when the job ends
- Revoking access = update the trust policy (instant, no pipeline changes)
- Third-party keys (Supabase, Stripe, etc.) still use CI/CD secrets -- that is expected
```

## Pattern 3: Operator Access via Session Manager

When operators need to access a running instance (for debugging, log inspection, or emergency response), they use session-based access. No SSH keys. No VPN. No bastion host with a public IP. The session is authenticated via SSO, logged end-to-end, and terminates automatically.

### Architecture

```
Operator (authenticated via SSO)
    |
    | Cloud CLI / Console
    |
Session Manager Service
    |
    | Encrypted session channel (no SSH, no port 22)
    |
Target Instance (private subnet, no public IP)
    |
    +-- Session logged (every keystroke)
    +-- Session expires automatically
    +-- No SSH key on instance
    +-- No SSH daemon required
```

### What This Eliminates

| Traditional Approach | Problem | Session Manager Approach |
|---------------------|---------|------------------------|
| SSH key pair (.pem file) | Shared, copied, never rotated | SSO-authenticated session |
| Bastion host with public IP | Attack surface, SSH brute force | No public IP, no SSH port |
| VPN to reach private instances | VPN config files shared, complex setup | Direct session via cloud API |
| Port forwarding via SSH tunnel | Key management, complex commands | Managed port forwarding via session |

### Session-Based Port Forwarding

For database access during debugging, use session-based port forwarding instead of SSH tunnels:

```bash
# Traditional (BAD): SSH tunnel with key file
ssh -i ~/.ssh/mykey.pem -L 5432:db.internal:5432 ec2-user@bastion.myapp.com

# Modern (GOOD): Session manager port forwarding (AWS example)
aws ssm start-session \
  --target i-0abc123def456 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"portNumber":["5432"],"localPortNumber":["5432"],"host":["db.internal"]}'

# The operator is authenticated via SSO
# The session is logged
# No SSH key exists
# No VPN required
```

## Credential Audit: What Should Not Exist

Run this audit regularly. Any "yes" answer is a security finding that must be remediated.

| Check | Expected | Finding If Present |
|-------|----------|-------------------|
| IAM access keys for any human user | None exist | Critical: static human credentials |
| SSH key pairs in any region | None exist | Critical: legacy access pattern |
| CI/CD platform secrets containing cloud credentials | None exist | Critical: static pipeline credentials |
| VPN configuration files | None exist | Important: replace with session manager |
| `.pem` files in any repository | None exist | Critical: committed credentials |
| Long-lived API keys for third-party services | Secrets manager with rotation | Important: move to secrets manager |
| Database passwords on developer machines | IAM auth or SSO-integrated access | Important: credential sprawl |

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Federated human identity | IAM Identity Center (SSO) | Cloud Identity + Workforce Identity Federation | Microsoft Entra ID |
| External IdP integration | SAML to IAM Identity Center | SAML/OIDC to Cloud Identity | SAML/OIDC to Entra ID |
| CI/CD OIDC federation | STS AssumeRoleWithWebIdentity | Workload Identity Federation | Federated Credentials |
| Session-based instance access | SSM Session Manager | IAP Tunneling | Azure Bastion |
| Credential-free CLI | `aws sso login` | `gcloud auth login` | `az login` |
| Port forwarding (no SSH) | SSM port forwarding | IAP TCP tunneling | Azure Bastion tunneling |
| Permission sets / roles | IAM Identity Center Permission Sets | IAM Roles + Conditions | Entra ID Roles + PIM |
| Temporary credential issuance | STS (Security Token Service) | Service Account Key alternatives | Managed Identity tokens |
| Audit trail | CloudTrail | Cloud Audit Logs | Azure Activity Log |

## Examples

Working implementations in `examples/`:
- **`examples/oidc-federation.md`** -- Complete OIDC setup for CI/CD with trust policies, role definitions, and workflow configuration
- **`examples/sso-permission-sets.md`** -- SSO configuration with three permission tiers, group assignments, and per-account access scoping

## Review Checklist

When designing or reviewing credential management:

- [ ] No IAM access keys exist for any human user
- [ ] No SSH key pairs exist in any region or account
- [ ] No `.pem` files exist in any repository or developer machine
- [ ] No VPN configuration files are required for cloud access
- [ ] CI/CD pipelines authenticate via OIDC federation (no stored cloud credentials)
- [ ] OIDC trust policies restrict role assumption to specific repositories
- [ ] All human access flows through SSO with an external identity provider
- [ ] MFA is enforced at the identity provider level
- [ ] SSO session duration is 12 hours or less
- [ ] Three permission tiers exist: Admin, Developer, ReadOnly
- [ ] Developers have read-only access to production (with targeted exceptions for debugging)
- [ ] Instance access uses session manager (no SSH, no VPN)
- [ ] All sessions are logged and auditable
- [ ] Offboarding an employee requires only disabling their IdP account
- [ ] Database access uses team-based roles, not individual credentials
- [ ] Third-party service credentials that cannot use OIDC are stored in encrypted CI/CD secret stores or cloud secrets managers (not in code, not in .env files)
