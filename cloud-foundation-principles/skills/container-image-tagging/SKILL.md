---
name: container-image-tagging
description: "This skill should be used when the user is building Docker images, configuring container registries, designing image tagging strategies, setting up registry lifecycle policies, debugging production incidents that require tracing running code, or discussing OCI labels and build metadata. Covers git SHA tagging, the traceability chain from container to source code, registry retention policies, OCI build labels, and why date-based or environment-based tags fail."
version: 1.0.0
---

# Tag Every Image with the Git SHA, or Accept Chaos

At 3am during an incident, the first question is always the same: "what code is running?" If the answer requires digging through CI/CD logs, cross-referencing deployment timestamps, or asking a colleague who might remember which build went out Tuesday, you have already lost critical minutes. A container image tagged with the full git commit SHA answers the question instantly. You look at the running container, read the image tag, and you have the exact commit. From there, one command shows you every line of code in production.

The `latest` tag is the root of a particularly insidious class of failures. Two services pulling `latest` five minutes apart may receive different images. A rollback to `latest` deploys whatever happens to be newest, which may be the broken version you are trying to escape. Environment-based tags like `staging` or `production` silently mutate, destroying the ability to reproduce issues. The only tag that is both immutable and traceable is the git commit SHA.

## The Tagging Format

Every container image receives exactly one meaningful tag: the full 40-character git commit SHA. Short SHAs are not acceptable -- they can collide as repository history grows, and they provide no benefit since the tag is never typed by hand.

```bash
# The only acceptable tagging pattern
IMAGE_TAG=$(git rev-parse HEAD)
# Result: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0

docker build -t myorg/myapp:${IMAGE_TAG} .
docker push registry.example.com/myorg/myapp:${IMAGE_TAG}
```

### Good vs. Bad Tagging Patterns

| Pattern | Example | Verdict | Why |
|---------|---------|---------|-----|
| Full git SHA | `myapp:a1b2c3d4e5f6...` | **Correct** | Immutable, traceable to exact commit |
| `latest` | `myapp:latest` | **Dangerous** | Mutable, two pulls can get different images, rollback is meaningless |
| Short SHA | `myapp:a1b2c3d` | **Risky** | Collisions grow with repo size, loses traceability precision |
| Date-based | `myapp:2025-03-15` | **Broken** | Multiple builds per day, no code traceability, timezone confusion |
| Build number | `myapp:build-142` | **Fragile** | CI-system-specific, lost if CI rebuilt, no direct link to code |
| Environment | `myapp:production` | **Dangerous** | Mutable like `latest`, silently changes, impossible to diff |
| Semver only | `myapp:1.2.3` | **Incomplete** | Required for production deploys, but insufficient alone -- must always accompany the SHA tag for traceability |

### Additional Tags and Deployment References

Every image is SHA-tagged at build time. For production deployments, a semver release tag is required -- it signals an explicit promotion decision, not just "the latest build."

- **Dev environments** deploy using the SHA tag directly (every merge to main triggers a deploy)
- **Production** deploys using a semver tag (`1.2.3`) that points to a previously built, SHA-tagged image

The image is built once and tagged with the SHA. When promoting to production, CI adds the semver tag to the existing image -- no rebuild. Both tags point to the same image digest.

```bash
# At build time: tag with SHA (mandatory, every build)
docker tag myorg/myapp:${GIT_SHA} registry.example.com/myorg/myapp:${GIT_SHA}
docker push registry.example.com/myorg/myapp:${GIT_SHA}

# At release time: add semver tag to the existing image (required for prod)
docker tag myorg/myapp:${GIT_SHA} registry.example.com/myorg/myapp:1.2.3
docker push registry.example.com/myorg/myapp:1.2.3
```

## The Traceability Chain

The git SHA tag creates an unbreakable chain from a running container back to the exact source code:

```
Running Container
    |
    | kubectl describe pod / ecs describe-tasks / az container show
    |
Image Tag: registry.example.com/myorg/myapp:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0
    |
    | git show a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0
    |
Exact Commit (author, timestamp, message, diff)
    |
    | git log, git blame, code review link
    |
Every Line of Source Code in Production
```

This chain answers every incident question: What changed? Who changed it? When? What was the review? What did the diff look like? All from one tag.

## OCI Labels for Build Metadata

Beyond the tag, embed build metadata directly into the image using OCI standard labels. This information survives even if the registry tag is deleted or overwritten.

```dockerfile
# Dockerfile
FROM node:20-alpine AS base
# ... build stages ...

FROM base AS production
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/myorg/myapp"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
LABEL org.opencontainers.image.version="${APP_VERSION}"
```

Pass build arguments at build time:

```bash
docker build \
  --build-arg GIT_SHA=$(git rev-parse HEAD) \
  --build-arg BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --build-arg APP_VERSION=$(git describe --tags --always) \
  -t myorg/myapp:$(git rev-parse HEAD) .
```

To inspect a running image's metadata:

```bash
docker inspect myorg/myapp:a1b2c3d4... --format '{{json .Config.Labels}}' | jq .
# {
#   "org.opencontainers.image.revision": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0",
#   "org.opencontainers.image.source": "https://github.com/myorg/myapp",
#   "org.opencontainers.image.created": "2025-03-15T14:30:00Z"
# }
```

## Registry Lifecycle Policies

Container registries accumulate images quickly. Without lifecycle policies, storage costs grow unbounded and old vulnerable images remain pullable. Define retention rules that keep what matters and clean up what does not.

### Recommended Policy

| Rule | Retention | Rationale |
|------|-----------|-----------|
| SHA-tagged images (dev builds) | Keep last 20 | Covers ~2-4 weeks of dev deployments, enough for rollback |
| Semver-tagged images (prod releases) | Keep all | Production releases are infrequent; needed for audits, compliance, and post-mortems |
| Untagged images (build layers) | Delete after 7 days | Build cache artifacts, no production value |

```hcl
# Terraform: Container registry lifecycle policy
# Note: semver-tagged images are kept indefinitely -- no expiry rule needed.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.myapp.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 20 SHA-tagged images (dev builds)"
        selection = {
          tagStatus     = "any"
          tagPrefixList = [""]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 10
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
```

### Why 20 SHA-Tagged Images?

Twenty SHA-tagged images covers approximately 2-4 weeks of active development builds. This provides enough rollback depth for dev environments while preventing unbounded growth. If a team deploys more frequently, increase the count proportionally. Production release images (semver-tagged) are kept indefinitely -- they are infrequent, storage cost is negligible, and you never want to explain in an audit why a production image was deleted.

## Why Other Tagging Schemes Fail

### Date-Based Tags (`myapp:2025-03-15`)

A team deploys twice on March 15th. Which image is `2025-03-15`? The first? The second? A hotfix at 11pm? Date tags have no disambiguation mechanism. They also provide zero information about what code is in the image. Incident responders must still search CI/CD logs to find the commit.

### Environment Tags (`myapp:production`)

Environment tags are mutable pointers. When you push a new `production` tag, the old image is not gone -- it is just untagged. If you need to roll back, what do you roll back to? The previous `production` tag no longer exists. You are left searching through image digests. Worse, if two services reference `myapp:production` and you push a new image between their deployments, they run different code with the same tag.

### Build Number Tags (`myapp:build-142`)

Build numbers are CI-system-specific. If you switch from one CI platform to another, build numbers reset. If you re-run a build, does `build-142` now contain different code? Build numbers also require a lookup table to map back to commits. The SHA eliminates the lookup entirely.

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Container registry | ECR (Elastic Container Registry) | Artifact Registry | ACR (Azure Container Registry) |
| Lifecycle policy | ECR Lifecycle Policy | Artifact Registry Cleanup Policies | ACR Retention Policy + Purge Tasks |
| Image scanning | ECR Enhanced Scanning (Inspector) | Artifact Analysis | ACR + Microsoft Defender |
| Registry authentication | `aws ecr get-login-password` | `gcloud auth configure-docker` | `az acr login` |
| Cross-account image pull | ECR Repository Policy (allow pull) | Artifact Registry IAM (roles/artifactregistry.reader) | ACR RBAC (AcrPull role) |
| Image immutability | ECR Image Tag Immutability | Artifact Registry tag immutability | ACR tag locking (preview) |

## Examples

Working implementations in `examples/`:
- **`examples/image-build-pipeline.md`** -- Complete CI pipeline that builds, tags with git SHA, adds OCI labels, pushes to registry, and applies lifecycle policies
- **`examples/registry-lifecycle-terraform.md`** -- Terraform configuration for a container registry with lifecycle policies, image scanning, and cross-account pull permissions

## Review Checklist

When designing or reviewing container image tagging:

- [ ] Every image is tagged with the full 40-character git commit SHA
- [ ] The `latest` tag is never used in deployment configurations or service definitions
- [ ] Environment tags (`staging`, `production`) are never used as deployment references
- [ ] Semver tags are required for production deploys and applied in addition to the SHA tag, never instead of it
- [ ] OCI labels embed build metadata (revision, source URL, build timestamp) in the image
- [ ] The Dockerfile accepts build arguments for metadata injection
- [ ] Registry lifecycle policies are defined in Terraform (not configured manually)
- [ ] SHA-tagged dev builds retain at least the last 20 versions; semver-tagged production images are kept indefinitely
- [ ] Untagged images are automatically cleaned up within 7 days
- [ ] Image tag immutability is enabled to prevent tag overwrites
- [ ] The traceability chain works end-to-end: running container to image tag to git SHA to source code
- [ ] CI pipeline fails if the git working directory is dirty (uncommitted changes would break traceability)
- [ ] Cross-account image pull permissions are configured for multi-account setups
- [ ] Image scanning is enabled on the registry to catch vulnerabilities at push time
