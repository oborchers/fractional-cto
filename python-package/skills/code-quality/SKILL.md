---
name: code-quality
description: "This skill should be used when the user is configuring Ruff, setting up mypy, adding type hints, choosing between mypy and pyright, writing py.typed markers, modernizing type annotations (PEP 695/649), using TYPE_CHECKING, setting up pre-commit hooks, configuring ruff format, choosing lint rule sets, or reviewing code quality tooling. Covers Ruff rule sets, mypy strict mode, pyright, modern typing patterns, pre-commit configuration, formatting, and complexity thresholds."
version: 1.0.0
---

# Use Ruff as the Single Linter and Formatter, Enforce Types with mypy

The modern Python code quality stack has consolidated around two tools: Ruff for linting and formatting, mypy (or pyright) for type checking. Ruff replaces Black, isort, flake8, pyupgrade, autoflake, and all flake8 plugins with a single Rust-powered binary that is 10-100x faster. Every major package -- FastAPI, Pydantic, httpx, Polars, Rich, pytest, attrs -- has migrated to Ruff. There is no credible alternative for new projects.

Without this consolidation, teams juggle conflicting configurations across six or more tools, deal with parser incompatibilities, and waste CI minutes. Without type checking in CI, a `py.typed` marker becomes a lie -- promising type safety to downstream consumers while delivering none.

## Ruff Rule Sets

Start with an explicit `select` of rules you want. Never use `select = ["ALL"]` with a long ignore list -- every Ruff update adds new rules that fire unexpectedly.

### Recommended starting set

```toml
[tool.ruff.lint]
select = [
    "F",      # Pyflakes -- undefined names, unused imports
    "E",      # pycodestyle errors
    "W",      # pycodestyle warnings
    "I",      # isort -- import sorting
    "N",      # pep8-naming -- naming conventions
    "UP",     # pyupgrade -- modernize syntax
    "B",      # flake8-bugbear -- common bugs
    "SIM",    # flake8-simplify -- simplifiable code
    "C4",     # flake8-comprehensions -- better comprehensions
    "RUF",    # Ruff-specific rules
    "PERF",   # Perflint -- performance anti-patterns
]
ignore = ["E501"]  # Line too long -- handled by formatter
```

**Also consider adding:**
- `"TCH"` -- moves type-only imports behind `if TYPE_CHECKING:` guards, reducing import time and breaking circular imports. Most valuable for typed libraries where downstream users pay your import cost.
- `"C90"` -- flags functions exceeding a cyclomatic complexity threshold (default 10). A code review guardrail for functions that are too complex to maintain and test. Pair with `[tool.ruff.lint.mccabe] max-complexity = 10`.

### Rule tier reference

| Tier | Prefixes | Notes |
|------|----------|-------|
| **Must have** | `F`, `E`, `W`, `I`, `UP`, `B` | Every top package enables these. Zero noise. |
| **Recommended** | `N`, `SIM`, `C4`, `RUF`, `PERF` | Enabled by Pydantic, Polars, attrs. Catches real issues. |
| **Consider** | `S`, `D`, `TCH`, `PT`, `C90`, `PLR` | Useful with targeted ignores. `TCH` valuable for typed libraries. |
| **Optional** | `A`, `FBT`, `ARG`, `ERA`, `ANN` | Opinionated or high false-positive rate. Cherry-pick individual rules. |

### Per-file ignores

Relax rules where they create noise rather than value:

```toml
[tool.ruff.lint.per-file-ignores]
"tests/**/*.py" = ["S101", "D", "ANN", "PLR2004"]
"__init__.py" = ["F401"]   # Allow unused imports (re-exports)
```

## Ruff Configuration

```toml
[tool.ruff]
target-version = "py310"    # Match your requires-python lower bound
line-length = 88            # Black default, de facto standard
src = ["src"]               # Critical for correct first-party import detection

[tool.ruff.lint.isort]
known-first-party = ["my_package"]

[tool.ruff.format]
docstring-code-format = true
```

Set `src = ["src"]` when using src layout. Without it, Ruff cannot distinguish first-party from third-party imports and isort grouping breaks silently.

## Formatting with Ruff Format

Use `ruff format` as a drop-in Black replacement. Same defaults (line length 88, double quotes, magic trailing comma respected), but 30-100x faster.

| Setting | Keep Default | Change Only If |
|---------|-------------|----------------|
| `quote-style = "double"` | Yes | Team strongly prefers single quotes |
| `line-length = 88` | Yes | Corporate standard requires different |
| `skip-magic-trailing-comma = false` | Yes | Never change -- preserves developer formatting intent |
| `docstring-code-format = true` | Enable this | No reason not to |

## Type Checking: mypy vs pyright

| Aspect | mypy | pyright |
|--------|------|---------|
| **Use when** | Need plugins (pydantic, django, sqlalchemy) | Want fastest checks, strictest analysis |
| **Strictness** | `strict = true` flag | `typeCheckingMode = "strict"` |
| **Speed** | Moderate (use daemon mode) | Consistently fast |
| **IDE** | External tool | Powers VS Code Pylance |
| **Plugin support** | Rich ecosystem | Limited |

**For library authors:** Run both. Different checkers catch different issues. Pydantic, FastAPI, and httpx do this.

### mypy strict configuration

```toml
[tool.mypy]
python_version = "3.10"
strict = true
warn_return_any = true
warn_unused_configs = true
enable_error_code = ["ignore-without-code", "redundant-cast", "truthy-bool"]

[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false
```

Always specify error codes in `# type: ignore[error-code]`. Bare `# type: ignore` silences all errors on the line, hiding real bugs. Ruff rule `PGH003` catches this automatically.

### pyright configuration (for libraries running both checkers)

```toml
[tool.pyright]
pythonVersion = "3.10"
typeCheckingMode = "standard"
reportUnnecessaryTypeIgnoreComment = true
enableTypeIgnoreComments = false
```

`typeCheckingMode = "standard"` is the practical starting point -- strict pyright is significantly noisier than strict mypy, and most exemplar libraries (Pydantic, Flask, SQLAlchemy) do not use strict mode. `enableTypeIgnoreComments = false` separates suppression concerns: `# type: ignore[code]` is for mypy only, `# pyright: ignore[rule]` is for pyright only. This is the pattern typeshed uses and eliminates cross-contamination between the two checkers.

## Modern Type Hints

Use the newest syntax your minimum Python version supports. Ruff's `UP` rules auto-fix old patterns.

| Old Pattern | Modern Pattern | Since |
|-------------|---------------|-------|
| `List[str]`, `Dict[str, Any]` | `list[str]`, `dict[str, Any]` | Python 3.9 |
| `Optional[str]`, `Union[str, int]` | `str \| None`, `str \| int` | Python 3.10 |
| `TypeVar("T")` + `Generic[T]` | `class Foo[T]:` | Python 3.12 (PEP 695) |
| `TypeAlias = Union[...]` | `type Alias = str \| int` | Python 3.12 (PEP 695) |
| `from __future__ import annotations` | Remove it | Python 3.14 (PEP 649) |

### Ship `py.typed`

Every typed package must include an empty `py.typed` marker file and the `Typing :: Typed` classifier. Without it, type checkers ignore your annotations for downstream users. See the `project-structure` skill for the full explanation, file placement, and PEP 561 details.

### TYPE_CHECKING guard

Move type-only imports behind `TYPE_CHECKING` to avoid circular imports and reduce import time:

```python
from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from heavy_module import ExpensiveClass
```

Ruff's `TCH` rules detect imports that should be behind this guard.

**Pydantic and runtime annotation frameworks:** Do not guard imports behind `TYPE_CHECKING` if the type is used in Pydantic models, dataclasses with runtime validation, or any framework that evaluates annotations at runtime (serializers, dependency injection containers). Pydantic needs the actual class at runtime for validation -- guarding it behind `TYPE_CHECKING` causes `NameError`. When using `TCH` rules, configure Ruff to recognize your runtime annotation framework: `[tool.ruff.lint.flake8-type-checking] runtime-evaluated-base-classes = ["pydantic.BaseModel"]`.

## Pre-commit Hooks

Collapse the entire pre-commit config to two Ruff hooks plus basic file hygiene. Do not add mypy, pytest, or security scanners -- they are too slow for pre-commit and belong in CI.

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-toml
      - id: check-added-large-files
        args: ["--maxkb=500"]
      - id: check-merge-conflict
      - id: debug-statements

  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.9.7
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
```

Run `ruff` (linter with `--fix`) before `ruff-format` so auto-fixes are properly formatted.

## Reference Configuration

Complete `pyproject.toml` quality tooling section:

```toml
# -- Ruff ---------------------------------------------------------
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
known-first-party = ["my_package"]

[tool.ruff.lint.mccabe]
max-complexity = 10

[tool.ruff.format]
docstring-code-format = true

# -- mypy ----------------------------------------------------------
[tool.mypy]
python_version = "3.10"
strict = true
warn_return_any = true
warn_unused_configs = true
enable_error_code = ["ignore-without-code", "redundant-cast", "truthy-bool"]

[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false

# -- pyright (for libraries running both checkers) -----------------
[tool.pyright]
pythonVersion = "3.10"
typeCheckingMode = "standard"
reportUnnecessaryTypeIgnoreComment = true
enableTypeIgnoreComments = false

# -- Dependency group ----------------------------------------------
[dependency-groups]
lint = ["ruff>=0.9", "mypy>=1.14", "pyright>=1.1"]
```

## Review Checklist

When reviewing code for quality tooling and type safety:

- [ ] Ruff is the sole linter and formatter -- no Black, isort, flake8, or their plugins installed separately
- [ ] `tool.ruff.lint.select` uses explicit opt-in, not `select = ["ALL"]` with a long ignore list
- [ ] `src = ["src"]` is set in `[tool.ruff]` for src-layout projects
- [ ] `E501` is in the ignore list when using `ruff format` (formatter handles line length)
- [ ] mypy runs in strict mode (`strict = true`) with `enable_error_code = ["ignore-without-code"]`
- [ ] No bare `# type: ignore` comments -- all have specific error codes
- [ ] For library projects, pyright is configured alongside mypy (`typeCheckingMode = "standard"`, `enableTypeIgnoreComments = false`)
- [ ] `py.typed` marker file exists in the package root and is included in the wheel
- [ ] Type hints use modern syntax appropriate for the minimum Python version (`list[str]`, `str | None`)
- [ ] Pre-commit config contains only Ruff hooks and file hygiene -- no mypy, pytest, or security scanners
- [ ] `ruff` hook runs before `ruff-format` in pre-commit ordering
- [ ] Type checkers run in CI, not in pre-commit
- [ ] `per-file-ignores` relaxes rules for tests and `__init__.py` re-exports
- [ ] McCabe complexity threshold is set (`max-complexity = 10`) if `C90` is enabled
- [ ] `TYPE_CHECKING` guards do not hide types used by runtime validation frameworks (Pydantic, attrs, dataclasses)
