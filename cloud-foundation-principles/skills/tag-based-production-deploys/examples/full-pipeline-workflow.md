# Full Pipeline Workflow: From PR to Production

Complete GitHub Actions workflow set implementing the tag-based deployment model: CI validation on PR, dev auto-deploy on merge, and production tag-triggered deploy with approval gate and post-deploy verification.

## Workflow 1: CI Validation (Runs on Every PR)

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
  validate:
    name: Validate & Plan
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [dev, prod]
    steps:
      - uses: actions/checkout@v4

      - name: Run Pre-Commit Checks
        uses: pre-commit/action@v3.0.1

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsPlanRole
          aws-region: eu-west-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Terraform Init
        run: |
          cd infrastructure/${{ matrix.environment }}
          terraform init

      - name: Terraform Validate
        run: |
          cd infrastructure/${{ matrix.environment }}
          terraform validate

      - name: Terraform Plan
        id: plan
        run: |
          cd infrastructure/${{ matrix.environment }}
          terraform plan -no-color -out=tfplan 2>&1 | tee plan-output.txt
        continue-on-error: true

      - name: Post Plan to PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync(
              `infrastructure/${{ matrix.environment }}/plan-output.txt`, 'utf8'
            );
            const status = '${{ steps.plan.outcome }}' === 'success' ? '✅' : '❌';
            const body = `#### ${status} Terraform Plan: \`${{ matrix.environment }}\`

            <details><summary>Show Plan</summary>

            \`\`\`
            ${plan.substring(0, 60000)}
            \`\`\`

            </details>

            *Triggered by commit: \`${context.sha.substring(0, 8)}\`*`;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: body
            });

      - name: Fail on Plan Error
        if: steps.plan.outcome == 'failure'
        run: exit 1
```

## Workflow 2: Dev Auto-Deploy (Runs on Merge to Main)

```yaml
# .github/workflows/terraform-cd-dev.yml
name: Terraform CD (Dev)
on:
  push:
    branches: [main]
    paths: ["infrastructure/**"]

permissions:
  id-token: write
  contents: read

jobs:
  deploy-dev:
    name: Deploy to Dev
    runs-on: ubuntu-latest
    environment: development  # No approval required
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsDeployRole
          aws-region: eu-west-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Terraform Init
        run: |
          cd infrastructure/dev
          terraform init

      - name: Terraform Plan
        run: |
          cd infrastructure/dev
          terraform plan -no-color -out=tfplan

      - name: Terraform Apply
        run: |
          cd infrastructure/dev
          terraform apply tfplan

      - name: Health Check
        run: |
          for i in $(seq 1 10); do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.dev.myapp.com/health)
            if [ "$STATUS" = "200" ]; then
              echo "Dev health check passed"
              exit 0
            fi
            echo "Attempt $i: status $STATUS, retrying..."
            sleep 10
          done
          echo "Dev health check failed"
          exit 1
```

## Workflow 3: Production Tag-Triggered Deploy (Requires Approval)

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
  # Step 1: Generate the plan and store as artifact
  plan:
    name: Terraform Plan (Prod)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsDeployRole
          aws-region: eu-west-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Terraform Init
        run: |
          cd infrastructure/prod
          terraform init

      - name: Terraform Plan
        run: |
          cd infrastructure/prod
          terraform plan -no-color -out=tfplan 2>&1 | tee plan-output.txt

      - name: Display Plan Summary
        run: |
          echo "=== PLAN SUMMARY ==="
          cd infrastructure/prod
          grep -E "Plan:|No changes" plan-output.txt || echo "See full plan output"
          echo "===================="

      - name: Upload Plan Artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan-prod
          path: |
            infrastructure/prod/tfplan
            infrastructure/prod/plan-output.txt
          retention-days: 7

  # Step 2: Apply with manual approval gate
  apply:
    name: Terraform Apply (Prod)
    needs: plan
    runs-on: ubuntu-latest
    environment: production  # Requires manual approval (configured in GitHub Settings)
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::role/GithubActionsDeployRole
          aws-region: eu-west-1

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Download Plan Artifact
        uses: actions/download-artifact@v4
        with:
          name: tfplan-prod
          path: infrastructure/prod/

      - name: Terraform Init
        run: |
          cd infrastructure/prod
          terraform init

      - name: Terraform Apply
        run: |
          cd infrastructure/prod
          terraform apply tfplan

  # Step 3: Post-deployment verification
  verify:
    name: Verify Production
    needs: apply
    runs-on: ubuntu-latest
    steps:
      - name: Health Check
        run: |
          echo "Waiting 30 seconds for deployment to stabilize..."
          sleep 30
          for i in $(seq 1 10); do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://api.myapp.com/health)
            if [ "$STATUS" = "200" ]; then
              echo "Production health check passed"
              exit 0
            fi
            echo "Attempt $i: status $STATUS, retrying..."
            sleep 15
          done
          echo "Production health check FAILED after 10 attempts"
          exit 1

      - name: Smoke Tests
        run: |
          # Basic endpoint checks
          curl -sf https://api.myapp.com/health | jq .
          curl -sf https://api.myapp.com/version | jq .

          # Verify the deployed version matches the tag
          DEPLOYED_VERSION=$(curl -sf https://api.myapp.com/version | jq -r '.version')
          TAG_VERSION="${GITHUB_REF#refs/tags/}"
          echo "Deployed: $DEPLOYED_VERSION, Expected: $TAG_VERSION"
```

## Release Process (Developer Workflow)

```bash
# 1. Verify main branch is in good state
git checkout main
git pull origin main

# 2. Review what will be released
git log --oneline 1.2.2..HEAD

# 3. Create annotated tag
git tag -a 1.2.3 -m "Release 1.2.3: Add payment retry logic, fix timeout handling"

# 4. Push tag to trigger production pipeline
git push origin 1.2.3

# 5. Monitor the pipeline
# - Plan job runs automatically
# - Apply job waits for manual approval in GitHub
# - Reviewer inspects plan output, approves
# - Apply executes, verify runs health checks

# Rollback if needed:
# Simply deploy the previous known-good tag
git tag -a 1.2.4 -m "Rollback: revert to 1.2.2 codebase"
# Or re-trigger the previous tag's workflow
```

## GitHub Environment Configuration

Configure these settings in GitHub repository Settings > Environments:

**`development` environment:**
- No protection rules
- Auto-deploys on merge to main

**`production` environment:**
- Required reviewers: 2 (infrastructure team members)
- Wait timer: 0 (or set to deployment window if needed)
- Deployment branches: Tags only (semver pattern)
