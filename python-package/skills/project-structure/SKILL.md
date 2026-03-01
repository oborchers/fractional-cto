---
name: project-structure
description: "This skill should be used when the user is setting up a Python project structure, choosing between src/ and flat layout, organizing __init__.py files, creating a new package directory, or structuring a monorepo. Covers src/ layout, flat layout, __init__.py design, __all__ exports, _internal/ convention, py.typed marker, naming conventions, test placement, root-level files, and monorepo vs single-package patterns."
version: 1.0.0
---

# Use the src/ Layout and a Canonical Directory Structure

A broken project structure causes packaging bugs that only surface after publishing. The most common failure: tests pass locally because Python adds the working directory to `sys.path`, but the installed package is missing files. The src/ layout eliminates this entire class of bugs by design. Every packaging expert -- Hynek Schlawack, the PyPA, the Pallets team -- has converged on this layout. Projects like pytest, pip, Flask, Black, Hatch, and attrs all use it. No major project has ever migrated away from src/ layout.

## src/ Layout vs Flat Layout

Place the importable package inside a `src/` directory. This forces an editable install (`pip install -e .` or `uv pip install -e .`) before tests can import the package, proving that packaging works as part of normal development.

| Aspect | src/ Layout | Flat Layout |
|--------|------------|-------------|
| Test safety | Tests cannot accidentally import from working directory | Tests may pass even when packaging is broken |
| Tool defaults | Default for `hatch new`, `uv init --lib`, `pdm init` | Default for `flit init` (historical) |
| Used by | pytest, pip, Flask, Black, Hatch, attrs | FastAPI, Pydantic, httpx (predate consensus) |
| Recommendation | **Use for all new packages** | Only for existing projects already using it |

**Flat layout mitigation** (if you must keep it): add `--import-mode=importlib` to pytest and test against the built wheel in CI.

## Canonical Directory Structure

Start every new Python package from this structure:

```
my-package/                         # Repository root (kebab-case)
    src/
        my_package/                 # Importable package (snake_case)
            __init__.py             # Public API, __all__, version
            py.typed                # PEP 561 marker (empty file)
            core.py                 # Primary public module
            models.py               # Data models
            exceptions.py           # Custom exception hierarchy
            _internal/              # Private implementation
                __init__.py
                _utils.py
                _compat.py          # Python version shims
            cli.py                  # CLI entry point (see cli-architecture skill)
    tests/
        conftest.py                 # Shared fixtures
        test_core.py
        test_models.py
    docs/
        index.md
    pyproject.toml                  # Single configuration file
    README.md
    LICENSE
    CHANGELOG.md
    .gitignore
    .pre-commit-config.yaml
```

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| GitHub repository | kebab-case | `my-package` |
| PyPI distribution name | kebab-case | `my-package` |
| Import name | snake_case | `my_package` |
| `src/` directory | snake_case (matches import) | `src/my_package/` |
| `[project] name` in pyproject.toml | kebab-case | `name = "my-package"` |

PyPI normalizes names -- `my-package`, `my_package`, and `My.Package` resolve to the same package. Use kebab-case for distribution, snake_case for import. This is what Hatch, uv, and PDM generate by default.

## Test Placement and Organization

Place tests at the repository root in `tests/`, never inside the source package. Every major package (FastAPI, Pydantic, httpx, pytest, Flask, Hatch, attrs, Rich, Polars) follows this convention. Shipping tests inside the package wastes disk space and requires dev dependencies that users do not have.

**Flat with markers** (small to medium packages, used by httpx, FastAPI):
```
tests/
    conftest.py
    test_core.py
    test_client.py
```

**Directory separation** (large packages, used by pytest, Pydantic):
```
tests/
    conftest.py
    unit/
        test_parsing.py
    integration/
        test_database.py
```

**Mirror the source directory structure** -- the `tests/` directory must mirror `src/my_package/` exactly, with the same subdirectories and a `test_`-prefixed file for every source module. This 1:1 mapping makes it obvious where tests live and immediately reveals untested modules.

```
src/my_package/              tests/
    core.py            →         test_core.py
    models.py          →         test_models.py
    _internal/         →         _internal/
        _utils.py      →             test_utils.py
        _compat.py     →             test_compat.py
```

Include `__init__.py` in `tests/` only when using nested test subdirectories to prevent file name collisions.

## `__init__.py` Design

The `__init__.py` defines the public API surface. Follow these rules:

1. **Re-export from private modules** -- users import from `__init__.py`, never from `_internal`
2. **Define `__all__`** -- makes the public API explicit for tools, type checkers, and humans
3. **Keep it clean** -- imports, re-exports, and `__all__` only. No implementation logic
4. **Expose version via `_version.py`** -- generated by hatch-vcs or setuptools-scm, gitignored

```python
"""My Package -- a well-structured Python library."""

from my_package._version import __version__, __version_tuple__
from my_package._internal._client import Client
from my_package._internal._config import Settings
from my_package.exceptions import MyPackageError
from my_package.models import Item, User

__all__ = ["Client", "Settings", "Item", "User", "MyPackageError"]
```

**Why `_version.py` instead of `importlib.metadata.version()`?** The `importlib.metadata` approach reads from installed package metadata, which is a static snapshot frozen at install time. With VCS-based dynamic versioning (hatch-vcs, setuptools-scm), this causes problems: the version goes stale after new commits without reinstalling, it fails during builds if the backend imports your package (circular dependency), and it does not work at all when running from source without installing. The `_version.py` file is generated by the build hook from git tags, gitignored (it is derived state), and imported as a plain Python file with zero dependencies. See the `pyproject-toml` skill for the full hatch-vcs configuration.

For packages with heavy dependencies, use lazy imports via `__getattr__` (as Pydantic does). For most packages, eager imports are simpler and sufficient.

## `_internal/` Convention

Use underscore-prefixed modules or directories for private implementation. The public API lives in `__init__.py` re-exports; internals can change without notice.

| Approach | Used By | Best For |
|----------|---------|----------|
| `_internal/` directory | Pydantic | Large packages with many private modules |
| `_module.py` files | httpx, Rich | Medium packages, flat internal structure |
| Both combined | Flask/Werkzeug | Packages with deep module trees |

## `py.typed` Marker (PEP 561)

Create an empty file at `src/my_package/py.typed`. Without it, type checkers (mypy, pyright) ignore all type annotations in your package for downstream users -- even if every function is fully typed. Every well-maintained typed package ships this file: Pydantic, httpx, FastAPI, Rich, attrs, Flask.

Add the `Typing :: Typed` classifier to `pyproject.toml` to signal typing support on PyPI.

## Root-Level Files

| File | Status | Purpose |
|------|--------|---------|
| `pyproject.toml` | **Required** | Single source of truth for build, metadata, tool config |
| `README.md` | **Required** | GitHub landing page and PyPI description |
| `LICENSE` | **Required** | SPDX-compliant license text |
| `.gitignore` | **Required** | Python + IDE + OS patterns |
| `CHANGELOG.md` | Recommended | Keep a Changelog format |
| `CONTRIBUTING.md` | Recommended | Dev setup, PR conventions |
| `SECURITY.md` | Recommended | Vulnerability reporting policy |
| `.pre-commit-config.yaml` | Recommended | Ruff + file hygiene hooks |
| `Makefile` or `justfile` | Recommended | Common dev commands |

Consolidate all tool configuration into `pyproject.toml`. Do not create `.flake8`, `mypy.ini`, `pytest.ini`, `.isort.cfg`, or `tox.ini` -- Ruff replaces most linting tools, and pytest/mypy/coverage all support `pyproject.toml` natively.

## Monorepo and Workspace Patterns

| Scenario | Pattern | Example |
|----------|---------|---------|
| Standard Python library | Single repo, single package | httpx, Flask, attrs |
| Python + substantial Rust core | Dual repo (separate release cadences) | Pydantic + pydantic-core |
| Tightly coupled Python + Rust | True monorepo (co-versioned) | Polars |
| Multiple related Python packages | uv workspace with shared lockfile | Internal libraries, plugin architectures |

Default to single repo, single package. Use uv workspaces (`[tool.uv.workspace]` with `members = ["packages/*"]`) only when you maintain multiple related packages that share dependencies and should be tested together.

## Anti-Patterns

| Anti-Pattern | Consequence |
|-------------|-------------|
| Source code at repository root (no `src/` or package dir) | Ambiguous structure, breaks editable installs |
| Tests inside the source package | Wastes user disk space, test deps unavailable |
| `setup.py` as primary config | Deprecated, removed from pip 24.0 |
| `requirements.txt` for dependency specification | Not a packaging standard, use `pyproject.toml` |
| Implementation logic in `__init__.py` | Bloated imports, hard to maintain |
| Missing `py.typed` in a typed package | Type checkers ignore all annotations for users |
| Multiple config files for one tool | Fragmented, hard to discover and maintain |

## Review Checklist

When reviewing a Python project structure:

- [ ] Package uses src/ layout (`src/my_package/`)
- [ ] Tests live at repository root (`tests/`), not inside the package
- [ ] Every public source module has a corresponding test file (1:1 mapping)
- [ ] `pyproject.toml` is the single configuration file (no `setup.py`, `setup.cfg`, `tox.ini`)
- [ ] `__init__.py` defines `__all__` with curated re-exports
- [ ] No implementation logic in `__init__.py` -- only imports, re-exports, and version
- [ ] Version exposed via `_version.py` (generated by hatch-vcs or setuptools-scm, gitignored)
- [ ] `py.typed` marker exists at `src/my_package/py.typed`
- [ ] Private modules use underscore prefix (`_internal/`, `_utils.py`)
- [ ] Repository name uses kebab-case, import name uses snake_case
- [ ] Required root files present: `pyproject.toml`, `README.md`, `LICENSE`, `.gitignore`
- [ ] No `requirements.txt` used as primary dependency specification
- [ ] Documentation follows Diataxis structure in `docs/`
- [ ] No scattered config files (`.flake8`, `mypy.ini`, `pytest.ini`) -- all in `pyproject.toml`
