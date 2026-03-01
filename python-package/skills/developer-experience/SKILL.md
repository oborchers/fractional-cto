---
name: developer-experience
description: "This skill should be used when the user is writing a CONTRIBUTING.md, setting up developer onboarding, creating a Makefile or justfile, adding issue templates, adding PR templates, writing a README, creating a CODE_OF_CONDUCT.md, setting up CODEOWNERS, adding .editorconfig, configuring devcontainers, labeling good first issues, or building project community and governance. Covers one-command dev setup, task automation, contributor funnel, and community health files."
version: 1.0.0
---

# Make Contributing Effortless

The single biggest factor in whether someone contributes to a project is how fast they can get a working development environment. If clone-to-passing-tests takes more than 60 seconds, every additional minute costs potential contributors. FastAPI, Pydantic, and httpx all converge on the same pattern: one prerequisite (uv), one command (`uv sync --group dev`), and every common task wrapped in a Makefile target. Invest in developer experience early -- every minute spent here pays back tenfold in contributor time saved.

## One-Command Dev Setup

Target clone-to-running-tests in under 60 seconds. The modern standard uses uv with a committed lock file.

```bash
git clone https://github.com/org/my-package
cd my-package
uv sync --group dev     # Creates venv, installs package + all dev deps
uv run pytest           # Tests pass on first try
```

**What makes this possible:**

- Commit `uv.lock` to the repo for deterministic installs across machines
- Use PEP 735 dependency groups (`[dependency-groups]` in `pyproject.toml`) with a `dev` group
- Require no environment variables or config files to get started
- Rely on uv to install the correct Python version automatically

| Step | Legacy (2020) | Modern (2026) |
|------|---------------|---------------|
| Install Python | `pyenv install 3.x` | uv handles it |
| Create virtualenv | `python -m venv .venv` | `uv sync` creates it |
| Activate | `source .venv/bin/activate` | Not needed (`uv run`) |
| Install deps | `pip install -r requirements-dev.txt` | `uv sync --group dev` |
| Install package | `pip install -e .` | Included in `uv sync` |
| Run tests | `pytest` | `uv run pytest` |
| **Total commands** | **5-6** | **2** (clone + sync) |

## Task Automation with Makefile

Wrap every common operation in a Makefile target. Contributors type `make test` instead of remembering `uv run pytest --cov --cov-report=term-missing -x -v`. Use `make help` as the default target to make commands discoverable.

**Required targets:**

| Target | Purpose |
|--------|---------|
| `make dev` | Install all dev dependencies + pre-commit hooks |
| `make test` | Run tests with coverage |
| `make test-fast` | Run tests without coverage (`-x -q`) |
| `make lint` | Run Ruff check + mypy |
| `make format` | Run Ruff format + fix |
| `make docs` | Serve docs locally with live reload |
| `make build` | Build sdist + wheel |
| `make clean` | Remove build artifacts and caches |
| `make help` | Show available targets (default goal) |

**Every CI step must map to a Makefile target.** `make lint` locally runs the same checks as the lint CI job. If contributors cannot reproduce CI locally, they will push-and-pray.

Use justfile instead of Makefile only for team projects where contributors can install `just`. For open source libraries, Makefile is the safe default because it is pre-installed on macOS and Linux.

## CONTRIBUTING.md

Include a CONTRIBUTING.md in the repository root. GitHub surfaces it automatically when users open issues and PRs. Structure it as a funnel from easiest to hardest contributions, following FastAPI's exemplary pattern.

**Required sections (in order):**

1. **Welcome message** -- thank potential contributors, set the tone
2. **Ways to contribute** -- list non-code contributions first (bug reports, docs, reviews)
3. **Prerequisites** -- document the single prerequisite (uv installation command)
4. **Development setup** -- exact shell commands, copy-pasteable
5. **Running tests** -- full suite, single file, pattern match, coverage
6. **Code style** -- tools used (Ruff, mypy), how to run them, pre-commit setup
7. **Making changes** -- branch naming, commit conventions, PR process
8. **Documentation** -- how to build and preview docs locally
9. **Changelog entries** -- Towncrier fragment format if applicable
10. **Getting help** -- link to GitHub Discussions

**Rules for the contributing guide:**

- Start with the easiest contributions (starring the repo, helping others on issues)
- Provide exact shell commands for every step -- never say "set up your environment"
- Explain the PR review process: who reviews, expected turnaround, merge strategy
- Test the commands in your contributing guide in CI to prevent documentation drift

## Issue and PR Templates

### Issue Templates

Place YAML form templates in `.github/ISSUE_TEMPLATE/`. Use structured forms instead of freeform markdown. Provide separate templates for bug reports and feature requests.

**Bug report template must collect:**
- Description, steps to reproduce (with code block placeholder), expected vs actual behavior
- Package version, Python version, operating system (as dropdown)
- Additional context (optional)

**Feature request template must collect:**
- Problem or motivation, proposed solution (with code block placeholder)
- Alternatives considered, willingness to submit a PR (as dropdown)

**Disable blank issues** in `.github/ISSUE_TEMPLATE/config.yml` with `blank_issues_enabled: false`. Redirect questions to GitHub Discussions via `contact_links`. Redirect security reports to the security advisory page.

### PR Template

Place at `.github/pull_request_template.md`. Keep it short -- five to seven checklist items is the sweet spot. Templates with 20 checkboxes get ignored.

**Required checklist items:** tests added/updated, documentation updated, changelog entry added, CI passes, self-reviewed the diff. Include a type-of-change section (bug fix, feature, breaking change, docs, refactoring).

## Community Health Files

### CODE_OF_CONDUCT.md

Adopt the Contributor Covenant v2.1. Place it at `CODE_OF_CONDUCT.md` in the repository root. Designate specific enforcement contacts (not just "the project team"). Its absence signals that the project has not thought about community safety.

### CODEOWNERS

Place at `.github/CODEOWNERS`. Map file patterns to responsible reviewers. This automatically requests reviews from the right people and, with branch protection, requires their approval before merging.

```
*               @org/maintainers
/docs/          @org/docs-team
pyproject.toml  @org/maintainers
```

### .editorconfig

Ship an `.editorconfig` to enforce consistent whitespace regardless of individual editor settings. Set 4-space indent for Python, 2-space for YAML/JSON/TOML, tab for Makefile, and disable trailing whitespace trimming for Markdown.

### SECURITY.md

See the `security-supply-chain` skill for the full SECURITY.md template, reporting channels, and response timeline.

## README Best Practices

The README is the front page of the project. Most potential users decide within 30 seconds whether to keep reading.

**Required sections (in order):**
1. **Badges** -- PyPI version, Python versions, CI status, coverage (four badges, no more)
2. **One-sentence elevator pitch** -- what the package does and why it exists
3. **Features** -- 5-8 bullet points maximum
4. **Installation** -- `pip install my-package`
5. **Quick start** -- 5-15 lines of runnable code
6. **Documentation link** -- link to full docs
7. **Contributing link** -- link to CONTRIBUTING.md
8. **License**

| Include in README | Keep out of README |
|-------------------|--------------------|
| Badges (4 max) | Full API reference |
| One-sentence pitch | Changelog |
| Feature list (5-8 items) | Detailed contributing instructions |
| Installation command | Every configuration option |
| Minimal quick-start example | CI matrix badges |
| Link to full docs | Animated GIFs (unless CLI tool) |

## First-Time Contributor Experience

Label issues as `good first issue` to signal approachable entry points. Effective good-first-issues are well-scoped (one file change), documented (pointers to relevant code), and non-blocking (not on the critical path).

| Good "Good First Issue" | Bad "Good First Issue" |
|--------------------------|------------------------|
| "Add type annotation to `parse_config()` in `src/config.py`" | "Refactor the plugin system" |
| "Add test for empty input to `Client.fetch()`" | "Fix the CI pipeline" |
| "Fix typo in API reference for `validate()`" | "Improve performance" |

Structure the contribution path as a deliberate funnel: star/use the package, report a bug, fix a typo, add a test, implement a feature, review PRs, become a regular contributor. Each step should be explicitly documented and encouraged in CONTRIBUTING.md.

## Review Checklist

When reviewing a project for developer experience and community health:

- [ ] Clone-to-passing-tests works in under 60 seconds with `uv sync --group dev && uv run pytest`
- [ ] `uv.lock` is committed to the repository for deterministic installs
- [ ] Makefile or justfile exists with `help`, `dev`, `test`, `lint`, `format`, `docs`, `build`, and `clean` targets
- [ ] Every CI step maps to a local Makefile/justfile target
- [ ] CONTRIBUTING.md exists with copy-pasteable setup commands, test instructions, and PR process
- [ ] `.github/ISSUE_TEMPLATE/` contains bug report and feature request YAML form templates
- [ ] `.github/ISSUE_TEMPLATE/config.yml` disables blank issues and redirects questions to Discussions
- [ ] `.github/pull_request_template.md` exists with 5-7 checklist items
- [ ] CODE_OF_CONDUCT.md (Contributor Covenant v2.1) is present with designated enforcement contacts
- [ ] `.editorconfig` is present with correct settings for Python, YAML, Makefile, and Markdown
- [ ] README has badges (version, Python versions, CI, coverage), elevator pitch, install command, and quick-start example
- [ ] `good first issue` labels exist on well-scoped, documented issues
- [ ] CODEOWNERS file exists for multi-maintainer projects
- [ ] Contributing guide commands are tested in CI to prevent documentation drift
