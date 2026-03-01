# Pre-Commit Configuration for Terraform

Pre-commit hooks enforce code quality before changes enter the repository. These hooks catch formatting issues, syntax errors, linting violations, and security misconfigurations at the cheapest possible point -- the developer's machine.

## Installation

```bash
# Install pre-commit
pip install pre-commit

# Install hooks in the repository (run once per clone)
pre-commit install

# Run against all files (useful for CI or initial setup)
pre-commit run --all-files
```

## Configuration

```yaml
# .pre-commit-config.yaml
repos:
  # --- Terraform-specific hooks ---
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
        # What: Enforces canonical Terraform formatting
        # Why: Eliminates style debates in code review

      - id: terraform_validate
        # What: Runs `terraform validate` to catch syntax errors
        # Why: Catches invalid references, missing required arguments, type mismatches

      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
        # What: Runs TFLint with project-specific rules
        # Why: Catches provider-specific errors (invalid instance types,
        #       deprecated resources, naming convention violations)

      - id: terraform_checkov  # Optional but recommended
        args:
          - --args=--quiet
          - --args=--compact
          - --args=--skip-check=CKV_AWS_144   # Skip cross-region replication (not always needed)
        # What: Static security analysis of Terraform code
        # Why: Detects unencrypted resources, public access, missing logging,
        #       over-permissive IAM policies BEFORE they reach the repo

      - id: terraform_docs
        args:
          - --args=--config=.terraform-docs.yml
        # What: Auto-generates documentation from Terraform code
        # Why: Keeps README.md in sync with variables, outputs, and resources

  # --- General hooks ---
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: trailing-whitespace
        # Strips trailing whitespace from all files

      - id: end-of-file-fixer
        # Ensures files end with a newline

      - id: check-merge-conflict
        # Catches merge conflict markers (<<<<<<<, =======, >>>>>>>)

      - id: check-yaml
        # Validates YAML syntax

      - id: check-json
        # Validates JSON syntax

      - id: detect-private-key
        # Catches accidentally committed private keys (RSA, DSA, EC, PGP)

      - id: no-commit-to-branch
        args: [--branch, main, --branch, master]
        # Prevents direct commits to main/master (force use of PRs)
```

## TFLint Configuration

```hcl
# .tflint.hcl
config {
  # Use the Terraform recommended ruleset as baseline
  module = true
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS-specific rules (adjust for your provider)
plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# Custom rules
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}
```

## CI Verification

Run pre-commit in CI to catch cases where developers have not installed hooks locally:

```yaml
# .github/workflows/pre-commit.yml
name: Pre-Commit Checks
on:
  pull_request:
    paths:
      - "**/*.tf"
      - "**/*.tfvars"
      - ".pre-commit-config.yaml"
      - ".tflint.hcl"

jobs:
  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Install TFLint
        run: |
          curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
          tflint --init

      - name: Run Pre-Commit
        uses: pre-commit/action@v3.0.1
        with:
          extra_args: --all-files --show-diff-on-failure
```

## What Each Hook Catches

| Hook | Catches | Cost of Missing It |
|------|---------|-------------------|
| `terraform_fmt` | Inconsistent formatting | Noisy PRs with whitespace changes mixed into logic changes |
| `terraform_validate` | Syntax errors, invalid references | CI failure after 2-3 minutes of init + plan |
| `terraform_tflint` | Invalid instance types, deprecated resources | Terraform apply failure in real environment |
| `terraform_checkov` | Unencrypted S3 buckets, public RDS, over-permissive IAM | Security vulnerability in production |
| `detect-private-key` | Committed private keys | Security incident requiring key rotation |
| `no-commit-to-branch` | Direct push to main | Bypassed code review and CI checks |
