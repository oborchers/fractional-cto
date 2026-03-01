# Quality Gate Setup

Demonstrates the complete pre-commit, linting, and security scanning configuration for a Terraform module repository. These gates run locally on every commit and in CI on every pull request.

## Files to Add

```
tf-module-<name>/
+-- .pre-commit-config.yaml     <-- Hook definitions
+-- .tflint.hcl                 <-- Linting rules
+-- .checkov.yaml               <-- Security scan configuration (optional)
+-- Makefile                    <-- Developer convenience commands
```

## .pre-commit-config.yaml

```yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.2
    hooks:
      # Format all .tf files consistently
      - id: terraform_fmt

      # Lint for deprecated syntax, invalid references, cloud-specific rules
      - id: terraform_tflint
        args:
          - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl

      # Security and compliance scanning (optional -- can produce false positives;
      # evaluate signal-to-noise ratio before enabling as a blocking gate)
      - id: terraform_checkov
        args:
          - --args=--quiet
          - --args=--compact

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      # Prevent large files from being committed
      - id: check-added-large-files
        args: ['--maxkb=500']

      # Ensure files end with a newline
      - id: end-of-file-fixer

      # Trim trailing whitespace
      - id: trailing-whitespace
```

## .tflint.hcl

```hcl
config {
  # Enable module inspection (validate module sources and versions)
  module = true
}

# Terraform-native rules (recommended preset catches common mistakes)
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS-specific rules (change to google or azurerm for other clouds)
plugin "aws" {
  enabled = true
  version = "0.38.0"
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

### GCP Alternative

```hcl
# Replace the AWS plugin with GCP
plugin "google" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}
```

### Azure Alternative

```hcl
# Replace the AWS plugin with Azure
plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
```

## Makefile -- Developer Convenience

```makefile
.PHONY: init fmt lint security validate all

# Install pre-commit hooks
init:
	pre-commit install
	terraform init

# Format all Terraform files
fmt:
	terraform fmt -recursive

# Run TFLint
lint:
	tflint --init
	tflint

# Run Checkov security scan
security:
	checkov -d . --quiet --compact

# Run Terraform validate
validate:
	terraform validate

# Run all checks (same as pre-commit)
all: fmt lint security validate
	@echo "All checks passed"
```

## CI Pipeline Integration

### GitHub Actions

```yaml
# .github/workflows/pr-checks.yml
name: Terraform Checks

on:
  pull_request:
    paths:
      - '**.tf'
      - '**.tfvars'
      - '.tflint.hcl'

jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.8.0"

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: TFLint
        uses: terraform-linters/setup-tflint@v4
        with:
          tflint_version: "v0.54.0"
      - run: |
          tflint --init
          tflint

      - name: Checkov Security Scan
        uses: bridgecrewio/checkov-action@v12
        with:
          directory: .
          quiet: true
          compact: true
```

### GitLab CI

```yaml
# .gitlab-ci.yml
terraform-checks:
  image: hashicorp/terraform:1.8
  stage: validate
  before_script:
    - apk add --no-cache curl
    - curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
  script:
    - terraform fmt -check -recursive
    - tflint --init && tflint
  rules:
    - changes:
        - "**/*.tf"
        - ".tflint.hcl"
```

## What Each Gate Catches

### terraform_fmt -- Formatting

```hcl
# Before fmt (inconsistent spacing)
resource "aws_s3_bucket" "data" {
bucket = "my-bucket"
  tags={
    Name ="data"
  }
}

# After fmt (consistent spacing)
resource "aws_s3_bucket" "data" {
  bucket = "my-bucket"
  tags = {
    Name = "data"
  }
}
```

### terraform_tflint -- Linting

```
# Catches invalid instance types
Warning: "t1.micro" is previous generation instance type. (aws_instance_previous_type)

# Catches undocumented variables
Warning: variable "env" has no description. (terraform_documented_variables)

# Catches naming violations
Warning: resource name "MyBucket" must match snake_case. (terraform_naming_convention)
```

### terraform_checkov -- Security

```
# Catches unencrypted storage
Check: CKV_AWS_145: "Ensure that S3 Buckets are encrypted with KMS"
FAILED for resource: aws_s3_bucket.data

# Catches overly permissive security groups
Check: CKV_AWS_260: "Ensure no security group allows ingress from 0.0.0.0/0 to port 22"
FAILED for resource: aws_security_group.allow_ssh

# Catches missing logging
Check: CKV_AWS_18: "Ensure the S3 bucket has access logging enabled"
FAILED for resource: aws_s3_bucket.data
```

## First-Time Setup

```bash
# 1. Install pre-commit
pip install pre-commit

# 2. Install TFLint
brew install tflint  # macOS
# or: curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

# 3. Install Checkov
pip install checkov

# 4. Initialize hooks in the repo
cd tf-module-<name>
pre-commit install

# 5. Run against all files (first time)
pre-commit run --all-files
```

## Key Points

- Pre-commit hooks run automatically on every `git commit` -- developers cannot skip quality checks
- Two required gates (formatting, linting) plus one optional gate (security scanning) -- Checkov is valuable but can produce false positives depending on your codebase
- The same checks run locally and in CI, preventing "works on my machine" discrepancies
- TFLint plugins are cloud-specific -- swap the AWS plugin for GCP or Azure as needed
- Checkov catches security misconfigurations that TFLint does not (encryption, public access, logging)
- The Makefile provides individual commands for running each gate independently during development
