---
name: pyproject-toml
description: "This skill should be used when the user is configuring pyproject.toml, choosing a build backend, declaring dependencies, setting up dependency groups, configuring tool settings, defining entry points, or managing package versioning. Covers PEP 621 metadata, hatchling vs setuptools vs flit-core vs maturin, PEP 735 dependency groups, PEP 639 SPDX licenses, dynamic versioning with hatch-vcs, dependency version constraints, console scripts, and tool configuration consolidation."
version: 1.0.0
---

# Configure Everything in pyproject.toml

`pyproject.toml` is the single source of truth for a Python package: build system, metadata, dependencies, and tool configuration. As of pip 24.0, `setup.py install` is no longer supported. Every major package -- Pydantic, httpx, Flask, pytest, attrs, Ruff -- has migrated. There is no reason to use `setup.py`, `setup.cfg`, or `requirements.txt` as primary configuration for any new package.

## Anatomy: The Four Sections

Every `pyproject.toml` contains four logical sections. Keep them in this order:

1. **`[build-system]`** -- declares the build backend (PEP 517/518)
2. **`[project]`** -- standardized metadata (PEP 621)
3. **`[dependency-groups]`** -- dev-only dependencies (PEP 735)
4. **`[tool.*]`** -- tool-specific configuration (pytest, mypy, ruff, coverage)

## Build Backend Selection

Use hatchling for new pure-Python packages. It is PyPA-maintained, fast, extensible, and the default for `hatch new` and `uv init --lib`.

| Your Package | Use This Backend | Declaration |
|-------------|-----------------|-------------|
| Pure Python (new) | **hatchling** | `requires = ["hatchling"]` |
| Pure Python (very simple) | flit-core | `requires = ["flit_core>=3.10,<4"]` |
| Pure Python (legacy) | setuptools | `requires = ["setuptools>=75.0"]` |
| Rust extensions (PyO3) | maturin | `requires = ["maturin>=1.7,<2.0"]` |
| C/C++ with CMake | scikit-build-core | `requires = ["scikit-build-core>=0.10"]` |

**What top packages use:**

| Package | Backend | Reason |
|---------|---------|--------|
| Pydantic, httpx, Black, attrs | hatchling | Modern, clean, PyPA-aligned |
| Flask, Jinja2, Werkzeug | flit-core | Simple, minimal needs |
| pytest | setuptools | Historical, complex build |
| Polars, Ruff, pydantic-core | maturin | Rust (PyO3) bindings |

## PEP 621: Project Metadata

Only `name` and `version` are strictly required (unless `version` is listed in `dynamic`). For any public package, always set these recommended fields:

| Field | Purpose | Example |
|-------|---------|---------|
| `name` | PyPI distribution name (kebab-case) | `"my-library"` |
| `version` | PEP 440 version (or list in `dynamic`) | `"1.0.0"` |
| `description` | Single-line summary | `"A fast HTTP client"` |
| `readme` | PyPI long description | `"README.md"` |
| `license` | PEP 639 SPDX expression | `"MIT"` |
| `requires-python` | Minimum supported Python | `">=3.10"` |
| `authors` | Author list | `[{ name = "Jane Doe" }]` |
| `classifiers` | Trove classifiers (include `Typing :: Typed`) | See Reference Configuration |
| `dependencies` | Runtime dependencies (lower bounds only) | `["httpx>=0.27"]` |

Set `[project.urls]` with at minimum `Repository` and `Changelog` -- PyPI renders recognized keys (`Documentation`, `Issues`, `Funding`) with icons. See the Reference Configuration for a complete example.

## PEP 639: SPDX License Expressions

Use a plain SPDX string, not the legacy table form. All modern build backends and PyPI support this since 2024.

| Do | Do Not |
|----|--------|
| `license = "MIT"` | `license = { text = "MIT License" }` |
| `license = "Apache-2.0"` | `license = { file = "LICENSE" }` |
| `license = "MIT OR Apache-2.0"` | `license = "BSD"` (ambiguous -- which BSD?) |

## PEP 735: Dependency Groups

Use `[dependency-groups]` for dev-only dependencies. These are not published to PyPI and cannot be installed by end users.

```toml
[project.optional-dependencies]          # Published to PyPI -- user-facing feature variants
postgres = ["asyncpg>=0.29"]

[dependency-groups]                      # NOT published -- developer-only
test = ["pytest>=8.0", "pytest-cov>=6.0", "coverage[toml]>=7.6"]
lint = ["ruff>=0.9", "mypy>=1.14", "pyright>=1.1"]
dev = [{ include-group = "test" }, { include-group = "lint" }, "pre-commit>=4.0"]
```

**User-facing feature variants** (postgres, redis, HTTP/2) go in `[project.optional-dependencies]`. **Dev-only tools** (test, lint, docs) go in `[dependency-groups]`. Groups support `{ include-group = "name" }` for composition. Install with `uv sync --group dev` or `pip install --dependency-group test`.

## Dynamic Versioning

Derive the version from git tags to maintain a single source of truth. No version strings to update manually.

```toml
[project]
dynamic = ["version"]

[tool.hatch.version]
source = "vcs"

[tool.hatch.build.hooks.vcs]
version-file = "src/my_library/_version.py"
```

**Release workflow:** `git tag v1.2.3 && git push --tags` -- CI handles the rest.

**Runtime access** -- import from the generated `_version.py` (see `project-structure` skill for rationale):
```python
from my_library._version import __version__, __version_tuple__
```

For projects preferring explicit control, a static version in pyproject.toml (`version = "1.2.3"`) is valid for small or internal packages.

## Dependency Version Constraints

Use lower bounds only for libraries. Reflexive upper bounds create ecosystem-wide resolution conflicts.

| Situation | Pattern | Example |
|-----------|---------|---------|
| Default (libraries) | Lower bound only | `httpx>=0.27` |
| Tightly coupled (same team) | Exact or `==N.*` | `httpcore==1.*` |
| Known breakage at next major | Upper bound | `legacy-lib>=1.0,<2.0` |
| Patch-level compatibility | Compatible release | `some-api~=3.2.0` |
| Applications | Lock file | `uv.lock` (not pinned in pyproject.toml) |

**Conditional dependencies** for platform or Python version differences:

```toml
dependencies = [
    "tomli>=2.0; python_version < '3.11'",
    "colorama>=0.4; sys_platform == 'win32'",
]
```

## Entry Points and Console Scripts

Register CLI commands via `[project.scripts]`:

```toml
[project.scripts]
my-cli = "my_library.cli:main"
```

Register plugin entry points for discovery via `importlib.metadata`:

```toml
[project.entry-points."myframework.plugins"]
my-plugin = "my_plugin_package:PluginClass"
```

## Tool Configuration Consolidation

Consolidate all tool settings into `[tool.*]` sections of `pyproject.toml` where the tool supports it. Do not create `.flake8`, `mypy.ini`, `pytest.ini`, or `.coveragerc` -- Ruff, mypy, pytest, and coverage all read from `pyproject.toml` natively. Ruff replaces flake8, isort, Black, and pyupgrade as a single tool.

**Exceptions:** Tools that do not support `pyproject.toml` configuration keep their own files. The most common exception is `.pre-commit-config.yaml` -- pre-commit is a polyglot tool managing hooks across languages and requires its own YAML format.

The Reference Configuration below shows all recommended `[tool.*]` sections.

## Reference Configuration

A complete, production-ready `pyproject.toml` for a new pure-Python package:

```toml
[build-system]
requires = ["hatchling", "hatch-vcs"]
build-backend = "hatchling.build"

[project]
name = "my-library"
dynamic = ["version"]
description = "A well-packaged modern Python library"
readme = "README.md"
license = "MIT"
requires-python = ">=3.10"
authors = [{ name = "Jane Doe", email = "jane@example.com" }]
classifiers = [
    "Development Status :: 4 - Beta",
    "Programming Language :: Python :: 3",
    "Typing :: Typed",
]
dependencies = ["httpx>=0.27", "pydantic>=2.0"]

[project.urls]
Repository = "https://github.com/org/my-library"
Changelog = "https://github.com/org/my-library/blob/main/CHANGELOG.md"

[project.scripts]
my-cli = "my_library.cli:main"

[dependency-groups]
test = ["pytest>=8.0", "pytest-cov>=6.0", "coverage[toml]>=7.6"]
lint = ["ruff>=0.9", "mypy>=1.14", "pyright>=1.1"]
docs = [
    "mkdocs-material>=9.5",
    "mkdocstrings[python]>=0.27",
    "mkdocs-gen-files>=0.5",
    "mkdocs-literate-nav>=0.6",
    "mkdocs-section-index>=0.3",
    "mike>=2.1",
]
dev = [{ include-group = "test" }, { include-group = "lint" }, { include-group = "docs" }, "pre-commit>=4.0"]

[tool.hatch.version]
source = "vcs"

[tool.hatch.build.hooks.vcs]
version-file = "src/my_library/_version.py"

[tool.hatch.build.targets.wheel]
packages = ["src/my_library"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = ["--strict-markers", "--strict-config", "-ra"]
xfail_strict = true
filterwarnings = ["error"]
asyncio_mode = "auto"

[tool.mypy]
python_version = "3.10"
strict = true
warn_return_any = true
warn_unused_configs = true
enable_error_code = ["ignore-without-code", "redundant-cast", "truthy-bool"]

[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false

[tool.pyright]
pythonVersion = "3.10"
typeCheckingMode = "standard"
reportUnnecessaryTypeIgnoreComment = true
enableTypeIgnoreComments = false

[tool.ruff]
target-version = "py310"
line-length = 88
src = ["src"]

[tool.ruff.lint]
select = ["F", "E", "W", "I", "N", "UP", "B", "SIM", "C4", "RUF", "PERF", "TCH", "C90"]
ignore = ["E501"]

[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101", "PLR2004"]
"__init__.py" = ["F401"]

[tool.ruff.lint.isort]
known-first-party = ["my_library"]

[tool.ruff.lint.mccabe]
max-complexity = 10

[tool.ruff.format]
docstring-code-format = true

[tool.coverage.run]
source_pkgs = ["my_library"]
branch = true
parallel = true

[tool.coverage.report]
show_missing = true
fail_under = 85
exclude_also = ["if TYPE_CHECKING:", "@overload", "raise NotImplementedError", "\\.\\.\\."]
```

## Review Checklist

When reviewing pyproject.toml configuration:

- [ ] `[build-system]` declares a PEP 517 backend (hatchling, flit-core, setuptools, or maturin)
- [ ] `[project]` uses PEP 621 metadata, not `[tool.setuptools]` for name/version/dependencies
- [ ] `license` uses PEP 639 SPDX string format (`"MIT"`), not legacy table form
- [ ] `requires-python` is set to the minimum supported Python version
- [ ] `readme`, `description`, `authors`, and `classifiers` are populated
- [ ] Runtime dependencies use lower bounds only (`>=`), no reflexive upper bounds
- [ ] Dev dependencies use `[dependency-groups]` (PEP 735), not `[project.optional-dependencies]`
- [ ] `[project.optional-dependencies]` is reserved for user-facing feature variants only
- [ ] Version is either static or dynamic via hatch-vcs/setuptools-scm -- not duplicated across files
- [ ] All tool config (pytest, mypy, ruff, coverage) lives in `[tool.*]` sections, not separate files
- [ ] `[project.urls]` includes at least `Repository` and `Changelog`
- [ ] No `setup.py`, `setup.cfg`, `requirements.txt`, `.flake8`, `mypy.ini`, or `pytest.ini` exist
- [ ] Console scripts use `[project.scripts]`, not setuptools `console_scripts` entry point syntax
