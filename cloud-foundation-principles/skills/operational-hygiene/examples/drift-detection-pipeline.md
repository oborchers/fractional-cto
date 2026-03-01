# Drift Detection Pipeline

Demonstrates a scheduled CI/CD pipeline that runs `terraform plan` daily to detect infrastructure drift, alerts the team when out-of-band changes are found, and provides actionable context for investigation.

## GitHub Actions Workflow

```yaml
# .github/workflows/drift-detection.yml
name: Drift Detection

on:
  schedule:
    # Run daily at 6am UTC for production, weekly on Monday for dev
    - cron: "0 6 * * *"     # Daily (production layers)
    - cron: "0 7 * * 1"     # Weekly Monday (dev layers)
  workflow_dispatch:          # Allow manual triggers for investigation

permissions:
  id-token: write
  contents: read

jobs:
  detect-drift:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false       # Check all layers even if one has drift
      matrix:
        include:
          # Production layers -- checked daily
          - layer: "00_network"
            env: "prod"
            state_key: "network"
            schedule: "daily"
          - layer: "10_security"
            env: "prod"
            state_key: "security"
            schedule: "daily"
          - layer: "30_databases"
            env: "prod"
            state_key: "databases"
            schedule: "daily"
          - layer: "40_compute"
            env: "prod"
            state_key: "compute"
            schedule: "daily"
          - layer: "60_messaging"
            env: "prod"
            state_key: "messaging"
            schedule: "daily"
          - layer: "70_monitoring"
            env: "prod"
            state_key: "monitoring"
            schedule: "daily"
          # Dev layers -- checked weekly
          - layer: "00_network"
            env: "dev"
            state_key: "network"
            schedule: "weekly"
          - layer: "40_compute"
            env: "dev"
            state_key: "compute"
            schedule: "weekly"

    # Filter: daily schedule runs daily layers, weekly schedule runs weekly layers
    # workflow_dispatch runs everything
    env:
      IS_DAILY: ${{ github.event.schedule == '0 6 * * *' || github.event_name == 'workflow_dispatch' }}
      IS_WEEKLY: ${{ github.event.schedule == '0 7 * * 1' || github.event_name == 'workflow_dispatch' }}

    steps:
      - name: Check schedule filter
        id: filter
        run: |
          if [[ "${{ matrix.schedule }}" == "daily" && "${{ env.IS_DAILY }}" != "true" ]]; then
            echo "skip=true" >> $GITHUB_OUTPUT
          elif [[ "${{ matrix.schedule }}" == "weekly" && "${{ env.IS_WEEKLY }}" != "true" ]]; then
            echo "skip=true" >> $GITHUB_OUTPUT
          else
            echo "skip=false" >> $GITHUB_OUTPUT
          fi

      - name: Checkout
        if: steps.filter.outputs.skip != 'true'
        uses: actions/checkout@v4

      - name: Setup Terraform
        if: steps.filter.outputs.skip != 'true'
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Configure cloud credentials
        if: steps.filter.outputs.skip != 'true'
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::${{ secrets[format('AWS_ACCOUNT_ID_{0}', matrix.env)] }}:role/${{ matrix.env }}-cicd-readonly
          aws-region: eu-west-1

      - name: Terraform Init
        if: steps.filter.outputs.skip != 'true'
        working-directory: ${{ matrix.layer }}/${{ matrix.env }}
        run: terraform init -input=false

      - name: Detect Drift
        if: steps.filter.outputs.skip != 'true'
        id: drift
        working-directory: ${{ matrix.layer }}/${{ matrix.env }}
        run: |
          set +e
          terraform plan -detailed-exitcode -no-color -input=false > plan_output.txt 2>&1
          EXIT_CODE=$?
          set -e

          echo "exitcode=${EXIT_CODE}" >> $GITHUB_OUTPUT

          if [ $EXIT_CODE -eq 0 ]; then
            echo "status=clean" >> $GITHUB_OUTPUT
            echo "No drift detected in ${{ matrix.layer }}/${{ matrix.env }}"
          elif [ $EXIT_CODE -eq 2 ]; then
            echo "status=drift" >> $GITHUB_OUTPUT
            echo "DRIFT DETECTED in ${{ matrix.layer }}/${{ matrix.env }}"
            cat plan_output.txt
          else
            echo "status=error" >> $GITHUB_OUTPUT
            echo "ERROR running plan for ${{ matrix.layer }}/${{ matrix.env }}"
            cat plan_output.txt
          fi

      - name: Alert on Drift
        if: steps.filter.outputs.skip != 'true' && steps.drift.outputs.status == 'drift'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const planOutput = fs.readFileSync(
              '${{ matrix.layer }}/${{ matrix.env }}/plan_output.txt', 'utf8'
            );

            // Truncate if too long for the issue body
            const maxLength = 60000;
            const truncated = planOutput.length > maxLength
              ? planOutput.substring(0, maxLength) + '\n\n... (truncated)'
              : planOutput;

            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Drift detected: ${process.env.MATRIX_LAYER}/${process.env.MATRIX_ENV}`,
              body: `## Infrastructure Drift Detected\n\n` +
                `**Layer:** \`${process.env.MATRIX_LAYER}\`\n` +
                `**Environment:** \`${process.env.MATRIX_ENV}\`\n` +
                `**Detected at:** ${new Date().toISOString()}\n` +
                `**Run:** ${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}\n\n` +
                `### Action Required\n\n` +
                `Someone modified infrastructure outside of Terraform. Investigate and either:\n` +
                `1. **Import** the change into Terraform (if the change is desired)\n` +
                `2. **Revert** by running \`terraform apply\` (if the change was unauthorized)\n` +
                `3. **Document** the change in an ADR if it was an emergency\n\n` +
                `### Terraform Plan Output\n\n` +
                `\`\`\`\n${truncated}\n\`\`\`\n\n` +
                `### Resolution Deadline\n\n` +
                `Console-created resources must be imported into Terraform within 48 hours or deleted.`,
              labels: ['drift', 'infrastructure', process.env.MATRIX_ENV]
            });
        env:
          MATRIX_LAYER: ${{ matrix.layer }}
          MATRIX_ENV: ${{ matrix.env }}

      - name: Alert on Error
        if: steps.filter.outputs.skip != 'true' && steps.drift.outputs.status == 'error'
        uses: actions/github-script@v7
        with:
          script: |
            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Drift detection error: ${process.env.MATRIX_LAYER}/${process.env.MATRIX_ENV}`,
              body: `## Drift Detection Failed\n\n` +
                `Terraform plan failed for \`${process.env.MATRIX_LAYER}/${process.env.MATRIX_ENV}\`.\n\n` +
                `This may indicate a provider issue, state lock, or authentication problem.\n\n` +
                `**Run:** ${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`,
              labels: ['drift', 'infrastructure', 'error']
            });
        env:
          MATRIX_LAYER: ${{ matrix.layer }}
          MATRIX_ENV: ${{ matrix.env }}
```

## Drift Response Decision Tree

```
Drift detected
  |
  +-- Was it an emergency change?
  |     |
  |     +-- Yes: Import into Terraform + create ADR documenting the emergency
  |     |
  |     +-- No: Was it authorized?
  |           |
  |           +-- Yes: Import into Terraform + update code to match
  |           |
  |           +-- No: Revert by running terraform apply
  |
  +-- Is the drifted resource critical? (security group, IAM role, etc.)
        |
        +-- Yes: Escalate immediately, resolve within 4 hours
        |
        +-- No: Resolve within 48 hours
```

## Terraform Plan Exit Codes Reference

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | No changes needed | Infrastructure matches code. All clear. |
| 1 | Error running plan | Investigate: provider issue, state lock, auth failure |
| 2 | Changes detected | DRIFT: someone changed something outside Terraform |

The `-detailed-exitcode` flag is essential. Without it, `terraform plan` returns 0 for both "no changes" and "changes detected," making automated drift detection impossible.

## Key Points

- Drift detection runs daily for production layers and weekly for development layers
- `fail-fast: false` ensures all layers are checked even if one layer has drift -- you want the complete picture
- The pipeline uses a read-only IAM role (`cicd-readonly`) since it only runs `terraform plan`, never `terraform apply`
- Drift alerts are created as GitHub Issues with actionable context: what drifted, what to do about it, and a 48-hour resolution deadline
- The decision tree distinguishes between emergency changes (import + ADR), authorized changes (import + update code), and unauthorized changes (revert)
- Security-critical drift (security groups, IAM) gets a 4-hour escalation window
- `terraform plan -detailed-exitcode` is the mechanism: exit code 2 means drift, exit code 0 means clean
