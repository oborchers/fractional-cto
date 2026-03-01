---
name: using-python-package-principles
description: This skill should be used when the user asks "which Python packaging skill should I use", "show me all Python package principles", "help me set up a Python project", or at the start of any Python package creation, review, or modernization task. Provides the index of all 12 principle skills.
version: 1.0.0
---

<IMPORTANT>
When creating, reviewing, or modernizing any Python package — setting up project structure, configuring pyproject.toml, adding type hints, writing tests, building CI/CD pipelines, writing docs, releasing versions, designing APIs, packaging for distribution, securing the supply chain, or improving developer experience — invoke the relevant python-package skill BEFORE proceeding.

These are not suggestions. They are research-backed standards drawn from FastAPI, Pydantic, httpx, Ruff, uv, Polars, Rich, pytest, Hatch, Flask, attrs, Django, and 30+ PEPs.
</IMPORTANT>

## How to Access Skills

Use the `Skill` tool to invoke any skill by name. When invoked, follow the skill's guidance directly.

## Python Package Principles

| Skill | Triggers On |
|-------|-------------|
| `python-package:project-structure` | src/ vs flat layout, directory organization, `__init__.py` design, `_internal/` convention, `py.typed` marker, monorepo vs single-package |
| `python-package:pyproject-toml` | pyproject.toml configuration, PEP 621 metadata, build backends (hatchling/setuptools/flit/maturin), PEP 735 dependency groups, PEP 639 SPDX licenses, dynamic versioning, entry points |
| `python-package:code-quality` | Ruff configuration, mypy strict mode, modern type hints (PEP 695/649), `str \| None` vs `Optional`, pre-commit hooks, formatting rules |
| `python-package:testing-strategy` | pytest configuration, test organization, fixtures, parametrize, coverage (80-90%), async testing, Hypothesis, nox/tox, snapshot testing |
| `python-package:ci-cd` | GitHub Actions workflows, test matrix, trusted publishing (OIDC), release automation, caching, Dependabot/Renovate, SLSA/Sigstore, reusable workflows |
| `python-package:documentation` | MkDocs Material vs Sphinx, mkdocstrings/Griffe, Diataxis framework, Google-style docstrings, versioned docs, code examples in docs |
| `python-package:versioning-releases` | SemVer vs CalVer, PEP 440, Keep a Changelog, Towncrier, Conventional Commits, release process, deprecation strategy |
| `python-package:cli-architecture` | CLI framework selection (Click/Typer/argparse), cli.py vs cli/ directory, `__main__.py` delegation, exit codes, `[project.scripts]` entry points, subcommand organization |
| `python-package:api-design` | Public API surface (`__all__`), progressive disclosure, exception hierarchy, async/sync dual API, plugin architecture (pluggy/entry points/protocols), dependency injection |
| `python-package:packaging-distribution` | Pure Python vs compiled extensions, wheel format, platform tags, maturin/scikit-build-core, cibuildwheel, package size, namespace packages |
| `python-package:security-supply-chain` | Trusted publishing (OIDC), Sigstore/PEP 740, SLSA framework, pip-audit, SECURITY.md, dependency scanning, OpenSSF Scorecard |
| `python-package:developer-experience` | One-command dev setup, CONTRIBUTING.md, Makefile/justfile, issue/PR templates, code of conduct, governance models, README best practices |

## When to Invoke Skills

Invoke a skill when there is even a small chance the work touches one of these areas:

- Creating a new Python package from scratch
- Modernizing an existing package (setup.py to pyproject.toml, adding typing, upgrading CI)
- Reviewing a package for best practices compliance
- Setting up testing, CI/CD, or documentation
- Preparing a release or publishing to PyPI
- Designing a library's public API
- Hardening supply chain security

## The Three Meta-Principles

All principles rest on three foundations:

1. **Standards over convention** — Follow PEPs and official PyPA guidance, not tribal knowledge. `pyproject.toml` over `setup.py`, PEP 621 over custom metadata, PEP 735 over ad-hoc dev dependencies.

2. **Tooling-enforced** — Every rule must be enforced by a tool. Ruff for linting/formatting, mypy for types, pytest with `fail_under` for coverage, GitHub Actions for CI. If a human has to remember it, it will be forgotten.

3. **Exemplar-validated** — Every recommendation is validated against real-world exemplar packages (FastAPI, Pydantic, httpx, Ruff, uv, Polars). If the best packages don't do it, neither should you.
