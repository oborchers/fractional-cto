---
name: security-supply-chain
description: "This skill should be used when the user is setting up trusted publishing, configuring OIDC for PyPI, enabling Sigstore attestations, writing a SECURITY.md, running pip-audit, scanning for vulnerabilities, configuring Dependabot or Renovate, setting up CodeQL, working with OpenSSF Scorecard, enabling 2FA on PyPI, defending against typosquatting, or hardening CI permissions. Covers PEP 740, SLSA framework, SPDX license compliance (PEP 639), and supply chain security best practices."
version: 1.0.0
---

# Eliminate Secrets, Sign Everything, Scan Continuously

Supply chain attacks are the fastest-growing threat to open source. A single leaked PyPI API token can push a malicious release to millions of users. Trusted publishing eliminates long-lived tokens entirely. Sigstore attestations give users cryptographic proof of provenance. pip-audit catches known vulnerabilities before they ship. These are not optional hardening steps -- they are baseline requirements for any published package.

## Trusted Publishing (OIDC)

Trusted publishing is the single most important security improvement a package maintainer can make. It replaces long-lived API tokens with short-lived OIDC tokens that prove the publish request originated from a specific CI workflow.

| Aspect | API Tokens | Trusted Publishing |
|--------|-----------|-------------------|
| Lifetime | Long-lived (until revoked) | Seconds (per-job) |
| Scope | Can upload any version | Tied to specific workflow + repo |
| Storage | Must be stored as a secret | No secret to store |
| Rotation | Manual, often neglected | Automatic (every run) |
| Compromise impact | Attacker pushes malicious release | No credential to steal |

### Setup Steps

1. Configure PyPI at `pypi.org/manage/project/YOUR-PACKAGE/settings/publishing/` -- add GitHub Actions as a trusted publisher with owner, repo, workflow filename, and environment name
2. Create a GitHub Environment named `release` with required reviewers and deployment branch restrictions (`main` or `v*` tags)
3. Configure the publish workflow with `permissions: id-token: write` and `environment: release`

For new packages, use a "pending publisher" at `pypi.org/manage/account/publishing/` to claim the name before the first release.

**Delete all existing PyPI API tokens after migrating.** There is no reason to keep them.

## Sigstore Attestations (PEP 740)

Enable with one flag in the publish action:

```yaml
- uses: pypa/gh-action-pypi-publish@release/v1
  with:
    attestations: true
```

This generates Sigstore-based attestations proving who published the package, from which repository, and at which commit. Attestations are stored alongside each distribution file on PyPI and are verifiable by anyone:

```bash
python -m sigstore verify identity \
    my_package-1.0.0-py3-none-any.whl \
    --cert-identity "https://github.com/my-org/my-package/.github/workflows/publish.yml@refs/tags/v1.0.0" \
    --cert-oidc-issuer "https://token.actions.githubusercontent.com"
```

Separate build and publish into distinct CI jobs. Pass artifacts via `actions/upload-artifact`, never rebuild at publish time.

## SLSA Compliance

SLSA Level 2 is achievable today for any package using GitHub Actions with trusted publishing:

| Level | What It Requires | What Python Packages Need |
|-------|-----------------|--------------------------|
| L1 | Provenance exists, build documented | Any CI-based build |
| **L2** | Hosted build, signed provenance | GitHub Actions + trusted publishing + attestations |
| L3 | Hardened, isolated builds | `slsa-framework/slsa-github-generator` |

Target L2 as the minimum. L3 requires dedicated tooling but is achievable for high-value packages.

## Vulnerability Scanning with pip-audit

Run `pip-audit --strict` in every CI pipeline. It queries the OSV database covering NVD, GitHub Security Advisories, and other sources.

```yaml
# In CI
- name: Audit dependencies
  run: |
    pip install pip-audit
    pip-audit --strict --desc
```

Run on three triggers: every push to `main`, every pull request, and a weekly schedule (to catch newly disclosed CVEs). Generate an SBOM with `pip-audit --format cyclonedx --output sbom.json` for compliance records.

## SECURITY.md Template

Every published package needs a `SECURITY.md` at the repository root. Include these sections:

```markdown
# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 2.x     | Currently supported |
| 1.x     | Security fixes only (until YYYY-MM-DD) |
| < 1.0   | No longer supported |

## Reporting a Vulnerability

**Do NOT report security vulnerabilities through public GitHub issues.**

### Preferred: GitHub Security Advisories
Go to the Security Advisories page and click "Report a vulnerability".

### Alternative: Email
Send details to security@your-domain.com.

## Response Timeline

| Stage | Target |
|-------|--------|
| Acknowledgment | Within 48 hours |
| Initial assessment | Within 1 week |
| Fix development | Within 30 days (critical/high) |
| Public disclosure | Coordinated, typically 90 days |
```

Enable GitHub Private Vulnerability Reporting under `Settings > Security > Code security and analysis`.

## Dependency Security Automation

### Dependabot

See the `ci-cd` skill for the full Dependabot configuration with `uv` ecosystem support and groups. Ensure both `uv` (or `pip` for non-uv projects) and `github-actions` ecosystems are configured on a weekly schedule.

### License Compliance

Enforce allowed licenses in CI with pip-licenses:

```bash
pip-licenses \
    --allow-only="MIT;BSD-2-Clause;BSD-3-Clause;Apache-2.0;ISC;PSF-2.0;Python-2.0" \
    --fail-on="GPL-3.0-or-later;AGPL-3.0-or-later"
```

## PEP 639 SPDX License Declaration

Use an SPDX expression string, not the legacy table format. See the `pyproject-toml` skill for the full PEP 639 configuration and examples. Enforce license compliance in CI with `pip-licenses`.

## CI Permissions Hardening

Set restrictive defaults at the workflow level, grant specific permissions per job:

```yaml
permissions: read-all  # Workflow-level default

jobs:
  test:
    permissions:
      contents: read
  publish:
    permissions:
      id-token: write  # Only for trusted publishing
```

Pin GitHub Actions by full commit SHA for immutability. Version tags (e.g., `@v4`) are convenient and used in most CI configs (see `ci-cd` skill), but SHA pinning provides stronger supply chain guarantees since tags can be moved:

```yaml
# Most secure (SHA pinning)
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.7

# Acceptable (version tag pinning)
- uses: actions/checkout@v4
```

Never use `pull_request_target` with a checkout of the PR branch -- it grants write permissions and secret access to fork PRs.

## GitHub Security Features

Enable all of these under `Settings > Code security and analysis`:

- **Secret scanning** with push protection -- blocks commits containing detected secrets
- **CodeQL** code scanning -- detects SQL injection, insecure deserialization, hardcoded credentials, SSRF, ReDoS
- **Dependency graph** and **Dependabot alerts** -- maps your dependency tree and notifies on known vulnerabilities
- **Branch protection** on `main` -- require PR reviews, status checks, no force push

## OpenSSF Scorecard

Run the Scorecard action to get a 0-10 security score and a concrete improvement roadmap:

```yaml
- uses: ossf/scorecard-action@v2
  with:
    results_file: results.sarif
    publish_results: true
```

High-impact checks: Branch-Protection, Security-Policy, Dependency-Update-Tool, Signed-Releases, Token-Permissions, Vulnerabilities.

Add the badge to your README:

```markdown
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/YOUR-ORG/YOUR-PACKAGE/badge)](https://scorecard.dev/viewer/?uri=github.com/YOUR-ORG/YOUR-PACKAGE)
```

## 2FA and Account Security

Enable 2FA on PyPI immediately. Prefer hardware security keys (YubiKey, Titan) over TOTP. Generate and securely store recovery codes. With trusted publishing, you rarely need to log in to PyPI directly, reducing credential exposure.

## Review Checklist

When reviewing code for security and supply chain practices:

- [ ] Publishing uses trusted publishing (OIDC), not API tokens
- [ ] Sigstore attestations are enabled (`attestations: true` in publish action)
- [ ] Build and publish are separate CI jobs (artifacts passed via upload-artifact)
- [ ] GitHub Environment with required reviewers gates the publish job
- [ ] `pip-audit --strict` runs on every PR and on a weekly schedule
- [ ] `SECURITY.md` exists with reporting instructions and response timeline
- [ ] Dependabot or Renovate is configured for both uv (or pip) and github-actions ecosystems
- [ ] Workflow-level `permissions: read-all` is set, with per-job overrides
- [ ] GitHub Actions are pinned by full commit SHA
- [ ] Secret scanning with push protection is enabled
- [ ] CodeQL analysis runs on pushes to main and on PRs
- [ ] Branch protection requires PR reviews and passing status checks
- [ ] License declared using PEP 639 SPDX string format
- [ ] 2FA is enabled on PyPI account
- [ ] No `pull_request_target` with PR branch checkout
