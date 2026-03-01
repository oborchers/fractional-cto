# CI/CD Platform Consolidation Plan

Step-by-step plan for migrating from multiple CI/CD providers to a single unified platform, based on lessons learned from teams that consolidated from 3 providers to 1.

## Phase 1: Inventory (Week 1)

Create a complete inventory of every pipeline across all providers. Use this template:

### Pipeline Inventory Template

| # | Pipeline Name | Provider | Repo | Type | Trigger | Secrets Used | Runs/Week | Owner | Notes |
|---|--------------|----------|------|------|---------|-------------|-----------|-------|-------|
| 1 | api-build | CircleCI | myorg/api | App CI | Push to main | AWS_KEY, NPM_TOKEN | 40 | Backend team | |
| 2 | infra-plan | GitLab CI | myorg/infra | Infra CI | MR opened | AWS_KEY, GH_TOKEN | 15 | Platform team | |
| 3 | infra-apply | GitLab CI | myorg/infra | Infra CD | Tag push | AWS_KEY, GH_TOKEN | 3 | Platform team | Manual gate |
| 4 | etl-nightly | Jenkins | myorg/data | Data pipeline | Schedule (nightly) | AWS_KEY, DB_URL | 7 | Data team | Legacy |
| 5 | deploy-prod | GitHub Actions | myorg/api | App CD | Tag push | AWS_KEY | 5 | Backend team | |
| 6 | cert-check | Jenkins | - | Scheduled | Cron (weekly) | Slack webhook | 1 | Nobody | Legacy |

### Summary Questions to Answer

- How many total pipelines exist across all platforms?
- How many distinct secrets are duplicated across platforms?
- Which pipelines are business-critical (production deployments)?
- Which pipelines are candidates for removal (unused, legacy)?
- What is the monthly cost of each CI/CD platform?

## Phase 2: Classify and Prioritize (Week 1)

Group all pipelines by type and assign migration priority:

| Type | Count | Priority | Rationale |
|------|-------|----------|-----------|
| App CI (lint, test, build) | 12 | Medium | High volume but low risk to migrate |
| Infra CI (plan on PR) | 4 | High | Consolidates secrets and OIDC setup |
| Infra CD (apply on tag) | 4 | High | Critical path, benefits most from consolidation |
| App CD (deploy) | 6 | High | Visible improvement for developers |
| Scheduled jobs | 3 | Low | Low frequency, migrate last |
| Legacy/unused | 2 | Remove | Delete, do not migrate |

## Phase 3: Pilot Migration (Week 2)

Migrate 2-3 simple CI pipelines to the target platform. Choose pipelines that:
- Are non-critical (not production deployments)
- Have few secrets
- Have straightforward logic (no complex conditional steps)

### Pilot Checklist

- [ ] Create equivalent workflow on target platform
- [ ] Configure required secrets (or better: set up OIDC)
- [ ] Run both old and new pipeline in parallel for 5 days
- [ ] Compare outputs (same test results, same artifacts, same timing)
- [ ] Document any differences or issues
- [ ] Disable old pipeline only after 5 days of parity

## Phase 4: Create Templates (Week 3)

Extract reusable workflow templates from the successful pilots:

```yaml
# .github/workflows/templates/terraform-ci.yml
# Reusable workflow for Terraform CI (plan on PR)
name: Terraform CI Template
on:
  workflow_call:
    inputs:
      working_directory:
        required: true
        type: string
      environment:
        required: true
        type: string
      aws_region:
        required: false
        type: string
        default: "eu-west-1"

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
          aws-region: ${{ inputs.aws_region }}
      - uses: hashicorp/setup-terraform@v3
      - run: |
          cd ${{ inputs.working_directory }}
          terraform init
          terraform plan -no-color 2>&1 | tee plan.txt
      # ... post plan to PR
```

Services consume the template:

```yaml
# myapp-api/.github/workflows/terraform-ci.yml
name: Infra CI
on:
  pull_request:
    paths: ["infrastructure/**"]

jobs:
  plan-dev:
    uses: myorg/.github/.github/workflows/terraform-ci.yml@main
    with:
      working_directory: infrastructure/dev
      environment: dev

  plan-prod:
    uses: myorg/.github/.github/workflows/terraform-ci.yml@main
    with:
      working_directory: infrastructure/prod
      environment: prod
```

## Phase 5: Bulk Migration (Weeks 4-6)

Migrate remaining pipelines using the templates. Work in order of priority:

### Week 4: Infrastructure pipelines (highest impact)
- Infra CI: plan on PR
- Infra CD: apply on tag
- Set up OIDC federation (replace all stored AWS credentials)

### Week 5: Application pipelines
- App CI: lint, test, build, push image
- App CD: deploy on tag

### Week 6: Scheduled jobs and edge cases
- Drift detection
- Certificate expiry checks
- Cost report generation
- Any pipelines with special requirements (GPU, etc.)

## Phase 6: Parallel Run (Weeks 7-8)

Run both platforms simultaneously for 2 weeks:

| Day | Action |
|-----|--------|
| Day 1 | Enable new pipelines alongside old ones |
| Day 3 | Verify all new pipelines produce same results |
| Day 5 | Switch deployment triggers to new platform (old platform still runs for monitoring) |
| Day 7 | Disable triggers on old platform (pipelines still exist but do not run) |
| Day 10 | Verify no regressions, check monitoring coverage |
| Day 14 | Proceed to cutover |

## Phase 7: Cutover (Week 9)

- [ ] Disable all pipelines on old platforms
- [ ] Remove webhooks pointing to old platforms
- [ ] Update documentation and onboarding guides
- [ ] Delete stored secrets from old platforms
- [ ] Announce to team: all CI/CD is now on [platform]

## Phase 8: Decommission (Week 12)

After 30 days of grace period:

- [ ] Export any remaining artifacts or logs needed for audit
- [ ] Cancel subscriptions / remove accounts on old platforms
- [ ] Remove old platform's runner infrastructure
- [ ] Update ADR documenting the consolidation decision and outcome
- [ ] Calculate and document cost savings

## Expected Outcomes

| Metric | Before (3 platforms) | After (1 platform) |
|--------|---------------------|---------------------|
| Secret stores to manage | 3 | 1 (plus OIDC replaces most secrets) |
| YAML dialects to know | 3 | 1 |
| Onboarding time for CI/CD | "It depends on the repo" | "Here is how our CI/CD works" |
| Monthly CI/CD cost | $X + $Y + $Z (hard to compare) | $X (one bill) |
| Mean time to debug pipeline failure | 15-30 min (which platform?) | 5-10 min (one place to look) |
| Platforms to check during incident | 3 | 1 |
