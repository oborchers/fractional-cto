---
name: cli-architecture
description: "This skill should be used when the user is adding a CLI to a Python package, choosing between Click, Typer, and argparse, structuring cli.py or a cli/ directory, creating a __main__.py for python -m support, defining console script entry points, handling exit codes, or organizing subcommands. Covers framework selection, CLI module layout, __main__.py delegation pattern, exit code conventions, and subcommand organization."
version: 1.0.0
---

# CLI Architecture for Python Packages

Not every package needs a CLI, but when it does, the structure and framework choice have long-term consequences for maintenance, discoverability, and user experience. The Python ecosystem has converged on clear patterns -- 7 out of 13 surveyed top packages (httpx, Black, Hatch, Flask, cookiecutter, rich-cli, Typer itself) use Click directly. Typer wraps Click and is gaining adoption for simpler CLIs. argparse remains the choice when zero external dependencies is a hard requirement.

## Framework Selection

Choose the CLI framework based on your constraints and complexity:

| Your CLI | Use This Framework | Why |
|----------|-------------------|-----|
| Zero dependencies required | **argparse** (stdlib) | No external deps; used by pytest, pre-commit, Django |
| Simple-to-moderate, modern Python (3.10+) | **Typer** | Less boilerplate, leverages type hints, Click underneath |
| Complex with subcommand groups, plugins, custom types | **Click** | Battle-tested, explicit decorators, deep customization |
| Performance-critical tool | **Clap** (Rust) + maturin | Used by ruff, uv; not a Python CLI at all |

**What top packages use:**

| Package | Framework | Reason |
|---------|-----------|--------|
| Flask, Hatch, Black, httpx, cookiecutter | Click | Complex CLIs, plugin systems, mature ecosystem |
| fastapi-cli | Typer | Same author, type-hint-driven API |
| pytest, pre-commit | argparse | Zero-dependency policy |
| ruff, uv | Clap (Rust) | Performance-critical, not Python CLIs |

Click has ~530M monthly downloads; Typer has ~100M and growing. Typer IS Click underneath -- choosing Typer means you are using Click with a type-hint-based API surface. The Python Packaging User Guide now demonstrates Typer as its primary CLI example.

## CLI Module Layout

Two patterns, chosen by CLI complexity:

**Single `cli.py` file** (small-to-medium CLIs, used by Flask, httpx, pre-commit, fastapi-cli):

```
src/my_package/
    __init__.py
    __main__.py          # delegates to cli.main()
    cli.py               # all CLI logic here
```

**`cli/` directory with subcommand modules** (large CLIs, used by Hatch, pip, poetry):

```
src/my_package/
    __init__.py
    __main__.py          # delegates to cli.main()
    cli/
        __init__.py      # main group, imports subcommands
        build.py         # 'build' subcommand
        publish.py       # 'publish' subcommand
        env/
            __init__.py  # 'env' subcommand group
            create.py
            remove.py
```

Start with `cli.py`. Migrate to `cli/` when subcommands exceed 3-4 or when individual subcommands are complex enough to warrant their own modules.

## `__main__.py` for `python -m` Support

Every package with a CLI should provide `__main__.py` so users can run `python -m my_package`. The file purely delegates -- it never contains CLI logic.

```python
"""Allow running as: python -m my_package"""

from my_package.cli import main

raise SystemExit(main())
```

**Key conventions:**
- Use `raise SystemExit(main())` instead of `sys.exit(main())` -- avoids importing `sys` and works the same way
- The `main()` function must return an integer exit code (0 = success, 1 = error, 2 = usage error)
- `[project.scripts]` and `__main__.py` must call the **same function** -- users expect identical behavior from `my-cli` and `python -m my_package`

## Entry Point Registration

Register the CLI via `[project.scripts]` in `pyproject.toml` (see `pyproject-toml` skill for the full entry points section):

```toml
[project.scripts]
my-cli = "my_package.cli:main"
```

The entry point and `__main__.py` point to the same `main()` function:

| Invocation | Mechanism | Calls |
|-----------|-----------|-------|
| `my-cli` | `[project.scripts]` entry point | `my_package.cli:main()` |
| `python -m my_package` | `__main__.py` | `my_package.cli:main()` |

## Exit Code Handling

**Click-based packages:** Click handles exit codes automatically in `standalone_mode=True` (the default). `ctx.exit(code)` or raising `click.exceptions.Exit(code)` propagates to `sys.exit()`. Exit code 0 = success, 2 = usage error (bad arguments).

**Typer-based packages:** Uses `raise typer.Exit(code=N)` which delegates to Click's exit mechanism underneath.

**argparse-based packages:** Return an integer from `main()`, and `__main__.py` calls `raise SystemExit(main())`.

All frameworks follow the same convention:

| Exit Code | Meaning | When |
|-----------|---------|------|
| 0 | Success | Command completed normally |
| 1 | Error | Runtime failure (network error, file not found, validation failure) |
| 2 | Usage error | Bad arguments, missing required options |

## Anti-Patterns

| Anti-Pattern | Consequence |
|-------------|-------------|
| CLI logic in `__main__.py` | Cannot be imported or tested independently |
| `sys.exit()` scattered throughout CLI code | Hard to test, bypasses cleanup |
| `[project.scripts]` and `__main__.py` calling different functions | Users get different behavior depending on invocation |
| Missing `__main__.py` | `python -m package` does not work |
| Mixing Click and argparse in the same package | Inconsistent argument parsing, confusing error messages |

## Review Checklist

When reviewing a Python package CLI:

- [ ] CLI framework chosen appropriately (argparse for zero-deps, Typer for simple, Click for complex)
- [ ] CLI logic lives in `cli.py` or `cli/` directory, not in `__init__.py` or `__main__.py`
- [ ] `__main__.py` exists and purely delegates to `cli.main()`
- [ ] `[project.scripts]` and `__main__.py` call the same function
- [ ] `main()` returns an integer exit code
- [ ] `__main__.py` uses `raise SystemExit(main())`, not `sys.exit(main())`
- [ ] Subcommands organized in separate modules when CLI grows beyond 3-4 commands
