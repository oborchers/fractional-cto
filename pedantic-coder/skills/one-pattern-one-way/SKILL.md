---
name: one-pattern-one-way
description: "Use when a codebase has inconsistent coding patterns, mixed paradigms like callbacks alongside promises, multiple config loading approaches like os.getenv mixed with Pydantic BaseSettings, different validation libraries like Zod and Joi in the same project, inconsistent error handling strategies, or when reviewing PRs that introduce a second way of doing something the codebase already solves. Identifies pattern drift across configuration, error handling, validation, HTTP clients, logging, string constants, and defaults, then enforces standardization to exactly one approach per category."
version: 1.0.0
---

# One Problem, One Pattern, One Way

For each cross-cutting concern in a codebase, enforce exactly one pattern. The specific pattern matters less than having only one. A second approach creates ambiguity; a third makes the codebase a museum of abandoned conventions.

## Detection Workflow

To identify pattern violations in a codebase:

1. **Scan for parallel approaches** per category (see categories below)
2. **Count usages** of each approach — the dominant pattern wins by default
3. **Flag violations** in code review — reject PRs introducing a second pattern
4. **Migrate fully** if adopting a better pattern — refactor ALL usages in a single PR, never allow coexistence

## Categories and Recommended Patterns

For each category, pick one pattern and enforce it everywhere.

### Configuration

| Language | Pattern | Anti-patterns |
|----------|---------|---------------|
| Python | Pydantic `BaseSettings` | Raw `os.getenv()`, `dotenv.load()`, `config.yaml` |
| TypeScript | Zod schema validating `process.env` | Scattered `process.env` reads |
| Go | Struct with `envconfig` tags | Raw `os.Getenv()` calls |

**Detection:** `grep -rn "os.getenv\|os.environ\|dotenv" --include="*.py"` — any hits outside the settings module are violations.

**GOOD:**

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    redis_url: str
    stripe_api_key: str
    max_retry_attempts: int = 3
    model_config = {"env_file": ".env"}

settings = Settings()
```

### Error Handling

| Language | Pattern | Anti-patterns |
|----------|---------|---------------|
| Python | Custom exceptions from base `ServiceError` | Returning `None`, returning `(value, error)` tuples |
| TypeScript | Typed error classes from base `AppError` | Throwing plain strings, returning error objects |
| Go | `fmt.Errorf("%w", err)` with sentinel errors | Returning error strings, `panic()` for expected errors |

**Detection:** `grep -rn "return None\|return.*None.*error" --include="*.py"` in service layers — inconsistent with exception-based handling.

### Data Validation

| Language | Pattern | Anti-patterns |
|----------|---------|---------------|
| Python | Pydantic models at API boundary | Manual `if` checks, `cerberus`, `marshmallow` alongside Pydantic |
| TypeScript | Zod schemas at API boundary | Manual `typeof` checks, Joi alongside Zod |
| Go | `go-playground/validator` struct tags | Manual validation functions |

### HTTP Clients, Logging, String Constants

- **HTTP:** One wrapper with unified retry/timeout — no mixing `axios`, `fetch`, and `got`
- **Logging:** One structured logger — no mixing `slog`, `log.Printf`, and `fmt.Fprintf`
- **Constants:** One approach per language — Python: `StrEnum`; TypeScript: `as const`; Go: typed `const` blocks. Never inline strings for finite sets
- **Defaults:** One pattern — `??` everywhere or `||` everywhere, not a mix

## The Local Shortcut Rule

When a developer bypasses the established pattern (e.g., raw `os.getenv` instead of the Settings class), revert the shortcut — do not add a comment saying "use Settings." The fix is to add the field to the settings module and update downstream files.

**Resolution:** When the dominant pattern and a "better" pattern conflict, the dominant pattern wins unless all usages are migrated in a single PR.

## Examples

Working implementations in `examples/`:
- **`examples/pattern-consistency.md`** — Multi-language examples showing pattern drift vs pattern discipline for configuration, error handling, and validation in Python, TypeScript, and Go

## Review Checklist

- [ ] Configuration loaded through one mechanism — no raw `os.getenv`, `process.env`, or `os.Environ` outside config module
- [ ] Error handling uses one pattern — no mix of exceptions, return tuples, and None returns
- [ ] Data validation uses one library — no Zod in one module and Joi in another
- [ ] HTTP calls go through one client wrapper — no mix of axios, fetch, and got
- [ ] Logging uses one structured logger — no mix of `slog`, `log`, and `fmt.Println`
- [ ] String constants use one approach — all enums or all `as const`, never inline strings for finite sets
- [ ] Default values follow one pattern consistently
- [ ] No local shortcut introduces a second way of doing something already solved
- [ ] Pattern migration PRs convert ALL usages — no coexistence period
- [ ] Dominant pattern wins in disputes — consistency over perfection
