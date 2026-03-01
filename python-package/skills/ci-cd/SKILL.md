---
name: ci-cd
description: "This skill should be used when the user is setting up GitHub Actions, configuring CI/CD pipelines, creating test matrices, enabling trusted publishing with OIDC, automating PyPI releases, adding Dependabot or Renovate, or configuring Sigstore attestations. Covers workflow architecture, lint/type-check/test/build/publish jobs, caching, concurrency, reusable workflows, SLSA provenance."
version: 1.0.0
---

# Architect CI/CD as Separate Jobs with Trusted Publishing

A Python package without CI is a Python package with bugs you discover after release. Every serious package -- FastAPI, Pydantic, httpx, Ruff, uv, Polars -- follows the same five-stage pipeline: lint, type-check, test, build, publish. These stages run as separate jobs, not steps, because separate jobs enable parallel execution, clear failure attribution, and conditional downstream gates. The publish job uses OIDC trusted publishing with zero long-lived secrets -- API tokens are a supply chain risk that PyPI's trusted publishing eliminates entirely.

## Workflow Architecture

Structure every CI pipeline as a dependency graph of discrete jobs:

```
  lint + type-check   (parallel)
        |
      tests           (matrix: Python versions x OS)
        |
      build           (sdist + wheel, upload artifact)
        |
     publish          (trusted publishing, environment protection)
```

| Principle | Rule |
|-----------|------|
| Separate jobs, not steps | Each stage is its own job for parallelism and clear failure |
| `needs` for dependencies | Tests need lint + type-check; build needs tests; publish needs build |
| `fail-fast: false` | See all failures across the matrix, not just the first |
| Build once, publish once | Pass artifacts via `upload-artifact`/`download-artifact` -- never rebuild in publish |
| Concurrency control | Cancel stale runs with `concurrency` + `cancel-in-progress: true` |

## Test Matrix

Run the full Python version matrix on Linux. Add macOS and Windows only if your package has platform-specific behavior (path handling, native extensions, OS-specific dependencies). When cross-platform testing is needed, test oldest + newest Python versions only to keep CI costs manageable.

```yaml
strategy:
  fail-fast: false
  matrix:
    python-version: ["3.10", "3.11", "3.12", "3.13"]
    os: [ubuntu-latest]
    include:
      # Add these only if your package has platform-specific behavior
      - { python-version: "3.10", os: macos-latest }
      - { python-version: "3.13", os: macos-latest }
      - { python-version: "3.10", os: windows-latest }
      - { python-version: "3.13", os: windows-latest }
```

Upload coverage from a single matrix entry (latest Python, Linux) to avoid duplicate reports.

## Trusted Publishing (OIDC)

Publish to PyPI with zero secrets. The `pypa/gh-action-pypi-publish` action handles the OIDC token exchange automatically. No `password`, no `user`, no `PYPI_API_TOKEN`. See the `security-supply-chain` skill for the threat model and broader supply chain hardening context.

| Bad Pattern | Good Pattern |
|-------------|-------------|
| `password: ${{ secrets.PYPI_API_TOKEN }}` | No password field -- OIDC handles auth |
| Build and publish in the same job | Separate jobs with artifact passing |
| Publishing from a local machine | CI-only publishing with attestations |

**Setup on PyPI:** Project Settings > Publishing > Add trusted publisher with owner, repo, workflow filename, and environment name. For new packages, use a "pending publisher" at `pypi.org/manage/account/publishing/`.

**Required permissions on the publish job:**

```yaml
permissions:
  id-token: write       # OIDC token exchange
  attestations: write   # Sigstore attestations
  contents: read
```

**GitHub environment:** Create a `release` environment in Repository Settings > Environments. Add branch protection rules limiting to `main` or `v*` tags.

## Caching

Use `astral-sh/setup-uv@v5` with `enable-cache: true` in every job. This single line caches uv's global package cache keyed on the lock file.

```yaml
- uses: astral-sh/setup-uv@v5
  with:
    enable-cache: true
    cache-dependency-glob: "uv.lock"
```

For legacy pip projects, use `actions/setup-python@v5` with `cache: "pip"`.

## Release Automation

Trigger releases from GitHub Release events, not tag pushes. GitHub Releases provide a UI for release notes, drafts, and deliberate publishing.

```yaml
on:
  release:
    types: [published]
```

Use `hatch-vcs` for version-from-tag: tag `v1.2.3` produces version `1.2.3`. Requires `fetch-depth: 0` in the checkout step.

Configure auto-generated release notes in `.github/release.yml`:

```yaml
changelog:
  categories:
    - title: "Breaking Changes"
      labels: ["breaking"]
    - title: "Features"
      labels: ["enhancement", "feature"]
    - title: "Bug Fixes"
      labels: ["bug", "fix"]
    - title: "Documentation"
      labels: ["docs"]
    - title: "Internal"
      labels: ["internal", "ci", "dependencies"]
```

## Dependabot

Configure `.github/dependabot.yml` with both `uv` (or `pip` for non-uv projects) and `github-actions` ecosystems. Use `groups` to combine minor/patch updates into single PRs instead of one-PR-per-dependency.

```yaml
version: 2
updates:
  - package-ecosystem: "uv"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      python-packages:
        patterns: ["*"]
        update-types: ["minor", "patch"]

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

**Note:** Dependabot updates `pyproject.toml` but does not regenerate `uv.lock`. Add a CI step or post-update script to run `uv lock` after Dependabot PRs.

Use Renovate instead for monorepos, auto-merge rules, or when you need more granular control over update strategies.

## Anti-Patterns

| Anti-Pattern | Risk | Fix |
|-------------|------|-----|
| Long-lived API tokens | Token theft, supply chain attack | Trusted publishing (OIDC) |
| `fail-fast: true` (default) | Missing version-specific failures | `fail-fast: false` |
| Build + publish in same job | No artifact inspection, no separation | Separate jobs, artifact passing |
| Full matrix on all OS | Wasted CI minutes (macOS is 10x cost) | Full Linux matrix, oldest + newest elsewhere (only if needed) |
| `ruff check --fix` in CI | Violations pass silently | `ruff check` without `--fix` |
| No concurrency control | Stale runs waste minutes | `concurrency` + `cancel-in-progress` |
| Missing `fetch-depth: 0` | Wrong version with VCS versioning | Full checkout for tag-based versions |
| Pinning actions to `main` | Breaking changes, security risk | Pin to version tags (`@v4`, `@v5`) |

## Reference Configuration

### `.github/workflows/ci.yml`

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        with: { enable-cache: true }
      - run: uv run ruff check src tests
      - run: uv run ruff format --check src tests

  type-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        with: { enable-cache: true }
      - run: uv run mypy src
      # For libraries, also run pyright (see code-quality skill)
      # - run: uv run pyright src

  test:
    needs: [lint, type-check]
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        python-version: ["3.10", "3.11", "3.12", "3.13"]
        os: [ubuntu-latest]
        include:
          # Add these only if your package has platform-specific behavior
          - { python-version: "3.10", os: macos-latest }
          - { python-version: "3.13", os: macos-latest }
          - { python-version: "3.10", os: windows-latest }
          - { python-version: "3.13", os: windows-latest }
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v5
        with: { enable-cache: true }
      - run: uv run --python ${{ matrix.python-version }} pytest --cov --cov-report=xml
      - if: matrix.os == 'ubuntu-latest' && matrix.python-version == '3.13'
        uses: codecov/codecov-action@v5
        with: { token: "${{ secrets.CODECOV_TOKEN }}", files: coverage.xml }

  build:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: astral-sh/setup-uv@v5
        with: { enable-cache: true }
      - run: uv build
      - run: uvx twine check dist/*
      - uses: actions/upload-artifact@v4
        with: { name: dist, path: dist/, if-no-files-found: error }
```

### `.github/workflows/release.yml`

```yaml
name: Release
on:
  release:
    types: [published]

jobs:
  ci:
    uses: ./.github/workflows/ci.yml

  publish:
    needs: ci
    runs-on: ubuntu-latest
    environment: release
    permissions: { id-token: write, attestations: write, contents: read }
    steps:
      - uses: actions/download-artifact@v4
        with: { name: dist, path: dist/ }
      - uses: pypa/gh-action-pypi-publish@release/v1
        with: { attestations: true }
```

## Review Checklist

When reviewing CI/CD configuration:

- [ ] Lint job runs `ruff check` and `ruff format --check` without `--fix`
- [ ] Type-check job runs `mypy src` (or `pyright`) in parallel with lint
- [ ] Test matrix covers Python 3.10-3.13 on Linux; oldest + newest on macOS/Windows only if platform-specific behavior exists
- [ ] `fail-fast: false` is set on the test strategy
- [ ] `concurrency` with `cancel-in-progress: true` prevents stale runs
- [ ] uv caching enabled via `astral-sh/setup-uv` with `enable-cache: true`
- [ ] Build job uses `uv build` + `twine check` + `upload-artifact` as separate step from publish
- [ ] Publish job uses `pypa/gh-action-pypi-publish` with OIDC -- no API tokens or secrets
- [ ] `permissions: id-token: write` is set on the publish job
- [ ] Sigstore attestations enabled with `attestations: true`
- [ ] GitHub `release` environment configured with branch protection rules
- [ ] `fetch-depth: 0` set in checkout if using VCS-based versioning
- [ ] Dependabot or Renovate configured for both uv (or pip) and github-actions ecosystems
- [ ] Release triggered by `on: release: types: [published]`, not raw tag push
