# Container Image Build Pipeline

Complete CI pipeline that builds a container image, tags it with the git SHA, adds OCI labels, pushes to a container registry, and enforces tagging discipline.

## GitHub Actions Workflow

```yaml
# .github/workflows/ci.yml
name: Build and Push Container Image
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

permissions:
  id-token: write
  contents: read

env:
  REGISTRY: 123456789012.dkr.ecr.eu-west-1.amazonaws.com
  IMAGE_NAME: myapp-api

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for git describe

      # Fail if the working directory is dirty (uncommitted changes break traceability)
      - name: Verify Clean Working Directory
        run: |
          if [ -n "$(git status --porcelain)" ]; then
            echo "ERROR: Working directory is dirty. Image tags must map to exact commits."
            git status
            exit 1
          fi

      - name: Set Image Tags
        id: tags
        run: |
          GIT_SHA=$(git rev-parse HEAD)
          echo "git_sha=${GIT_SHA}" >> $GITHUB_OUTPUT
          echo "image_tag=${REGISTRY}/${IMAGE_NAME}:${GIT_SHA}" >> $GITHUB_OUTPUT
          echo "build_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> $GITHUB_OUTPUT

          # If this is a tag push, also set semver
          if [[ "${GITHUB_REF}" == refs/tags/[0-9]* ]]; then
            SEMVER="${GITHUB_REF#refs/tags/}"
            echo "semver_tag=${REGISTRY}/${IMAGE_NAME}:${SEMVER}" >> $GITHUB_OUTPUT
          fi

      # Authenticate via OIDC -- no stored credentials
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsBuildRole
          aws-region: eu-west-1

      - name: Login to ECR
        run: aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin ${{ env.REGISTRY }}

      - name: Build Image
        run: |
          docker build \
            --build-arg GIT_SHA=${{ steps.tags.outputs.git_sha }} \
            --build-arg BUILD_TIMESTAMP=${{ steps.tags.outputs.build_timestamp }} \
            --build-arg APP_VERSION=$(git describe --tags --always) \
            -t ${{ steps.tags.outputs.image_tag }} \
            .

      - name: Push SHA-Tagged Image
        if: github.event_name == 'push'  # Don't push on PRs
        run: docker push ${{ steps.tags.outputs.image_tag }}

      - name: Push Semver-Tagged Image
        if: steps.tags.outputs.semver_tag != ''
        run: |
          docker tag ${{ steps.tags.outputs.image_tag }} ${{ steps.tags.outputs.semver_tag }}
          docker push ${{ steps.tags.outputs.semver_tag }}

      - name: Verify Image Labels
        run: |
          echo "Verifying OCI labels on built image..."
          LABELS=$(docker inspect ${{ steps.tags.outputs.image_tag }} --format '{{json .Config.Labels}}')
          echo "$LABELS" | jq .

          # Verify the revision label matches the git SHA
          REVISION=$(echo "$LABELS" | jq -r '.["org.opencontainers.image.revision"]')
          if [ "$REVISION" != "${{ steps.tags.outputs.git_sha }}" ]; then
            echo "ERROR: Image revision label does not match git SHA"
            exit 1
          fi
          echo "Image labels verified successfully"
```

## Multi-Stage Dockerfile with OCI Labels

```dockerfile
# Dockerfile
FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# --- Production image ---
FROM node:20-alpine AS production

# Build arguments for OCI labels
ARG GIT_SHA="unknown"
ARG BUILD_TIMESTAMP="unknown"
ARG APP_VERSION="unknown"

# OCI standard labels -- embedded in image metadata
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.source="https://github.com/myorg/myapp-api"
LABEL org.opencontainers.image.created="${BUILD_TIMESTAMP}"
LABEL org.opencontainers.image.version="${APP_VERSION}"
LABEL org.opencontainers.image.title="myapp-api"
LABEL org.opencontainers.image.description="MyApp API Service"
LABEL org.opencontainers.image.vendor="myorg"

WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

# Non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "dist/main.js"]
```

## Inspecting a Running Container's Image Tag

During an incident, use these commands to identify exactly what code is running:

```bash
# AWS ECS: Find the image tag of a running task
aws ecs describe-tasks \
  --cluster myapp-prod \
  --tasks $(aws ecs list-tasks --cluster myapp-prod --service-name myapp-api --query 'taskArns[0]' --output text) \
  --query 'tasks[0].containers[0].image' \
  --output text
# Output: 123456789012.dkr.ecr.eu-west-1.amazonaws.com/myapp-api:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0

# Extract the git SHA from the image tag
IMAGE=$(aws ecs describe-tasks --cluster myapp-prod --tasks ... --query 'tasks[0].containers[0].image' --output text)
GIT_SHA="${IMAGE##*:}"
echo "Running commit: $GIT_SHA"

# Now look at the exact code
git show $GIT_SHA
git log --oneline $GIT_SHA -5
git diff $GIT_SHA~1 $GIT_SHA   # What changed in this commit

# Inspect OCI labels from the registry
aws ecr batch-get-image \
  --repository-name myapp-api \
  --image-ids imageTag=$GIT_SHA \
  --query 'images[0].imageManifest' \
  --output text | jq .
```
