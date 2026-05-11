# python-package

Research-backed best practices for building modern, production-grade Python packages. Distilled from studying FastAPI, Pydantic, httpx, Ruff, uv, Polars, Rich, pytest, Hatch, Flask, attrs, Django, and 30+ PEPs.

## What's Inside

**11 principle skills** covering every aspect of Python packaging:

| # | Skill | Key Topics |
|---|-------|------------|
| 01 | Project Structure | src/ layout, `__init__.py` design, `_internal/` convention, `py.typed` marker |
| 02 | pyproject.toml | PEP 621 metadata, build backends, PEP 735 dependency groups, PEP 639 SPDX licenses |
| 03 | Code Quality | Ruff as unified tool, mypy strict mode, modern type hints (PEP 695/649) |
| 04 | Testing Strategy | pytest strict configuration, coverage (80-90%), fixtures, async testing |
| 05 | CI/CD | GitHub Actions, trusted publishing (OIDC), test matrix, SLSA/Sigstore |
| 06 | Documentation | MkDocs Material, Diataxis framework, mkdocstrings, Google-style docstrings |
| 07 | Versioning & Releases | SemVer, PEP 440, Keep a Changelog, Towncrier, deprecation strategy |
| 08 | API Design | `__all__`, progressive disclosure, exception hierarchy, async/sync dual API |
| 09 | Packaging & Distribution | Wheels, platform tags, maturin, cibuildwheel, package size |
| 10 | Security & Supply Chain | Trusted publishing, Sigstore/PEP 740, SECURITY.md, pip-audit, OpenSSF Scorecard |
| 11 | Developer Experience | One-command setup, CONTRIBUTING.md, Makefile/justfile, issue templates |

**2 commands:**
- `/python-package:package-review` — Targeted review of current code against python-package principles
- `/python-package:package-audit [path]` — Full repository audit with migration path recommendations

**1 agent:**
- `package-reviewer` — Autonomous comprehensive package auditor (triggered by "review my Python package", "check if ready to publish", "modernize my package")

## Installation

```bash
claude --plugin-dir /path/to/python-package
```

## The Three Meta-Principles

1. **Standards over convention** — Follow PEPs and official PyPA guidance, not tribal knowledge
2. **Tooling-enforced** — Every rule must be enforced by a tool (Ruff, mypy, pytest, GitHub Actions)
3. **Exemplar-validated** — Every recommendation validated against real-world exemplar packages

## Reference Packages

These packages were studied across all 11 research documents:

- **FastAPI** — Perfect DX, type-first design, best-in-class docs
- **Pydantic** — Rust core + Python API, rigorous typing, v1-to-v2 migration model
- **httpx** — Clean async/sync API, excellent test suite
- **Ruff** — Rust-powered Python tool, blazing CI, excellent changelogs
- **uv** — Modern packaging tool, dogfoods its own ecosystem
- **Polars** — Rust core + Python bindings (PyO3/maturin), monorepo

## PEPs Referenced

PEP 440, 517, 518, 561, 621, 639, 649, 660, 695, 735, 740
