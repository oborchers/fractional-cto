---
name: tag-based-production-deploys
description: "This skill should be used when the user is designing CI/CD pipelines, configuring deployment triggers, setting up production release processes, implementing approval gates, configuring pre-commit hooks for Terraform, or distinguishing between development and production deployment strategies. Covers the environment/trigger matrix, git tag naming conventions, manual approval gates, pre-commit validation, the full pipeline flow from commit to production, and why branch-based production deploys are dangerous."
version: 1.0.0
---

# Dev Deploys on Push, Prod Deploys on Tag -- No Exceptions

There is a critical difference between "code was merged" and "we decided to release." Branch-based production deploys collapse this distinction. A merge to `main` is a code integration event -- it means the code passed review and tests. It does not mean someone decided the system is ready for production traffic. A git tag is a deliberate, auditable act. Someone looked at the state of `main`, decided it was ready, and explicitly said "this is a release." That intentionality is the difference between controlled releases and accidental deployments.

Development environments should deploy continuously from branch pushes -- fast feedback, low ceremony. Production environments deploy only from git tags -- explicit, deliberate, with approval gates. This separation provides an audit trail (tags are immutable references), intentionality (creating a tag is a conscious decision), rollback clarity (deploy the previous tag), and compliance evidence (every production change has a traceable trigger).

## The Environment/Trigger Matrix

| Environment | Trigger | Branch/Tag | Approval Required | Purpose |
|-------------|---------|------------|-------------------|---------|
| Dev | Push to `main` | Branch | None | Fast feedback, continuous integration |
| Production | Git tag creation | Semver (e.g., `1.2.3`) | Manual approval gate | Deliberate release with audit trail |

### Why This Matrix Works

**Dev deploys are cheap**. A broken dev environment wastes 30 minutes. The team fixes it and moves on. Speed matters more than ceremony. Push to the branch, deploy automatically, see results immediately.

**Production deploys are expensive**. A broken production environment wastes revenue, trust, and sleep. Ceremony matters more than speed. The extra 60 seconds to create a tag and approve a gate is trivially cheap insurance against accidental deployments.

## Tag Naming Convention

Use semantic versioning. The `v` prefix is optional -- both `v1.2.3` and `1.2.3` work with every major CI/CD platform's tag-based triggers. Pick one convention and stick with it.

```
Format:  <major>.<minor>.<patch>  or  v<major>.<minor>.<patch>
Example: 1.2.3

Hotfix:       1.2.4 (increment patch)

# Pre-release tags (1.2.3-rc.1) can be added when a staging environment is introduced.
```

### Creating a Release

```bash
# Ensure you are on the correct commit
git log --oneline -5

# Create an annotated tag (includes author and message)
git tag -a 1.2.3 -m "Release 1.2.3: Add payment retry logic, fix timeout handling"

# Push the tag to trigger the production pipeline
git push origin 1.2.3
```

**Annotated tags over lightweight tags**: Annotated tags (`git tag -a`) store the tagger's name, email, date, and a message. Lightweight tags (`git tag`) are just pointers. Annotated tags provide the audit trail that compliance requires -- who released, when, and why.

## The Full Pipeline Flow

The pipeline has distinct stages that separate validation from deployment. No stage is optional. The manual approval gate for production is non-negotiable.

```
Developer pushes code
    |
    v
[Pre-commit Hooks] -- Local, before code enters the repository
    | terraform_fmt, terraform_validate, tflint, checkov
    |
    v
[CI: Validate] -- Triggered on every push / pull request
    | Lint, test, build, terraform plan
    | Plan output posted as PR comment
    |
    v
[Merge to main] -- Code integration, not a release
    | Dev environment auto-deploys (branch trigger)
    |
    v
[Create git tag] -- Deliberate release decision
    | 1.2.3
    |
    v
[CD: Plan] -- Triggered by tag, runs terraform plan
    | Plan output stored as artifact
    |
    v
[CD: Approval Gate] -- Manual human approval
    | Reviewer inspects plan output
    | Approves or rejects
    |
    v
[CD: Apply] -- terraform apply with the approved plan
    | Resources created/modified/destroyed
    |
    v
[CD: Verify] -- Post-deployment validation
    | Health checks, smoke tests, monitoring check
```

## Pre-Commit Hooks: The First Gate

Pre-commit hooks catch problems before code enters the repository. They are the cheapest form of validation -- failures cost seconds, not minutes.

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
        # Enforces consistent formatting (no style debates in reviews)

      - id: terraform_validate
        # Catches syntax errors and invalid references

      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
        # Catches provider-specific errors (invalid instance types,
        # deprecated resources, naming violations)

      - id: terraform_checkov  # Optional but recommended
        args:
          - --args=--quiet
          - --args=--compact
        # Security scanning: detects unencrypted resources, public access,
        # missing logging, over-permissive IAM policies

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
      - id: detect-private-key
        # Catches accidentally committed private keys
```

Every developer installs pre-commit hooks. It is not optional. Add `pre-commit install` to the repository's onboarding documentation and verify it in CI by running `pre-commit run --all-files` as a CI step.

## CI Stage: Plan as PR Comment

When a pull request is opened, the CI pipeline runs `terraform plan` and posts the output as a PR comment. Reviewers see exactly what infrastructure changes the code will produce -- before it is merged.

```yaml
# .github/workflows/terraform-ci.yml
name: Terraform CI
on:
  pull_request:
    paths: ["infrastructure/**"]

permissions:
  id-token: write
  contents: read
  pull-requests: write

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsPlanRole
          aws-region: eu-west-1

      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Plan
        id: plan
        run: |
          cd infrastructure/dev
          terraform init
          terraform plan -no-color -out=tfplan 2>&1 | tee plan-output.txt

      - name: Post Plan to PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('infrastructure/dev/plan-output.txt', 'utf8');
            const body = `#### Terraform Plan
            \`\`\`
            ${plan.substring(0, 60000)}
            \`\`\`
            *Triggered by commit: \`${context.sha.substring(0, 8)}\`*`;
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });
```

## CD Stage: Tag-Triggered with Approval

The production deployment pipeline triggers only on git tag creation. It includes a mandatory manual approval gate that blocks `terraform apply` until a human reviews and approves the plan.

```yaml
# .github/workflows/terraform-cd-prod.yml
name: Terraform CD (Production)
on:
  push:
    tags: ["[0-9]*"]  # Matches semver tags (1.2.3); adjust to "v*" if using v-prefix

permissions:
  id-token: write
  contents: read

jobs:
  plan:
    runs-on: ubuntu-latest
    environment: production-plan
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsDeployRole
          aws-region: eu-west-1

      - uses: hashicorp/setup-terraform@v3

      - name: Terraform Plan
        run: |
          cd infrastructure/prod
          terraform init
          terraform plan -no-color -out=tfplan

      - name: Upload Plan
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: infrastructure/prod/tfplan

  apply:
    needs: plan
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval in GitHub settings
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsDeployRole
          aws-region: eu-west-1

      - uses: hashicorp/setup-terraform@v3

      - name: Download Plan
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: infrastructure/prod/

      - name: Terraform Apply
        run: |
          cd infrastructure/prod
          terraform init
          terraform apply tfplan

  verify:
    needs: apply
    runs-on: ubuntu-latest
    steps:
      - name: Health Check
        run: |
          for i in $(seq 1 10); do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.myapp.com/health)
            if [ "$STATUS" = "200" ]; then
              echo "Health check passed"
              exit 0
            fi
            echo "Attempt $i: status $STATUS, retrying..."
            sleep 10
          done
          echo "Health check failed after 10 attempts"
          exit 1
```

### The Manual Approval Gate Is Non-Negotiable

For production `terraform apply`, a human must review the plan output and explicitly approve. This is not about distrust of automation -- it is about catching the plan that says "3 resources to destroy" when you expected "1 resource to modify." Automated pipelines are excellent at doing exactly what they are told. A human reviewer catches when what-they-are-told is wrong.

Configure the approval gate in your CI/CD platform's environment protection rules:
- **Required reviewers**: At least 1 (recommend 2 for infrastructure changes)
- **Wait timer**: Optional, useful for scheduled maintenance windows
- **Branch restrictions**: Only allow deployments from protected branches or tags

## Good vs. Bad Deployment Patterns

```
BAD: Branch-based production deploys
- Merge to main auto-deploys to production
- Accidental merges cause accidental deployments
- No distinction between "code ready" and "release ready"
- Rollback means reverting commits and re-merging
- No audit trail of who decided to release

GOOD: Tag-based production deploys
- Merge to main deploys to dev only
- Production requires explicit git tag creation
- Clear distinction: merge = integration, tag = release
- Rollback means deploying the previous tag (instant)
- Full audit trail: who tagged, when, why (annotated tag message)
```

```
BAD: No approval gate for terraform apply
- CI/CD auto-applies infrastructure changes to production
- A plan that destroys a database executes without human review
- "We didn't mean to delete that" becomes a 4am incident

GOOD: Mandatory approval gate
- Plan output visible to reviewer before apply
- Reviewer verifies resource counts (create, modify, destroy)
- Unexpected destroys are caught before execution
- Apply only proceeds after explicit human approval
```

## Cloud Provider Translation

| Concept | AWS | GCP | Azure |
|---------|-----|-----|-------|
| Approval gate | GitHub Environments (protection rules) | Cloud Build Approval | Azure DevOps Approvals and Checks |
| Tag-based trigger | GitHub Actions `on: push: tags` | Cloud Build Trigger (tag) | Azure Pipelines `trigger: tags` |
| Plan artifact storage | GitHub Actions Artifacts | Cloud Storage | Azure Artifacts |
| Deployment environment | GitHub Environment | Cloud Deploy Target | Azure DevOps Environment |
| State locking | S3 native locking (`use_lockfile`) | GCS (native locking) | Azure Blob lease |
| OIDC for pipeline auth | STS AssumeRoleWithWebIdentity | Workload Identity Federation | Federated Credentials |

## Examples

Working implementations in `examples/`:
- **`examples/full-pipeline-workflow.md`** -- Complete GitHub Actions workflow set: CI validation on PR, dev auto-deploy on merge, production tag-triggered deploy with approval gate and post-deploy verification
- **`examples/pre-commit-config.md`** -- Pre-commit configuration with terraform_fmt, terraform_validate, tflint, checkov, and private key detection

## Review Checklist

When designing or reviewing deployment pipelines:

- [ ] Development environments deploy automatically from branch pushes (fast feedback)
- [ ] Production environments deploy only from git tag creation (explicit release)
- [ ] Git tags use semantic versioning (`1.2.3` or `v1.2.3` -- pick one convention)
- [ ] Tags are annotated (`git tag -a`) with a message describing the release
- [ ] A manual approval gate blocks `terraform apply` in production
- [ ] The approval gate requires at least one reviewer (two recommended for infrastructure)
- [ ] `terraform plan` output is posted as a PR comment for code review
- [ ] `terraform plan` output is stored as an artifact and used by the apply step (plan and apply use the same plan file)
- [ ] Pre-commit hooks are configured: terraform_fmt, terraform_validate, tflint (checkov optional but recommended)
- [ ] Pre-commit hooks are verified in CI (`pre-commit run --all-files`)
- [ ] Post-deployment verification (health checks, smoke tests) runs after every production deploy
- [ ] Rollback procedure is documented: deploy the previous tag
- [ ] No branch push ever triggers a production `terraform apply`
- [ ] CI/CD authenticates via OIDC federation, not stored credentials (see `zero-static-credentials` skill)
