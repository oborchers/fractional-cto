# pedantic-coder

A Claude Code plugin for developers who believe code quality lives in the details. Zero-tolerance enforcement of naming precision, casing consistency, structural symmetry, import discipline, and every small detail that separates clean code from correct code.

Your code works? Great. Now make it right.

## What It Does

When Claude is writing or reviewing code — naming variables, organizing files, establishing patterns, or cleaning up inconsistencies — the relevant principle skill activates automatically and enforces specific, non-negotiable standards.

This plugin provides **universal principles** that apply to every language, plus **language packs** with deep, language-specific pedantry for Python, TypeScript, and Go.

## The 11 Universal Principles

| # | Principle | Skill | The Pedantic Take |
|---|-----------|-------|-------------------|
| I | Every name is a contract | `naming-precision` | `data` is not a name. `temp` is not a name. Name it what it IS. |
| II | One convention, zero exceptions | `casing-law` | Mixed camelCase and snake_case in one file? Rewrite the file. |
| III | Spell it out or document it | `abbreviation-policy` | `btn` in one file, `button` in another? Pick one. Enforce it. |
| IV | Booleans are yes/no questions | `boolean-naming` | `is/has/can/should` prefix. Always positive. No exceptions. |
| V | Imports are your table of contents | `import-discipline` | Grouped, sorted, separated. One blank line between groups. No strays. |
| VI | Every file has the same shape | `declaration-order` | Constants, types, classes, functions — predictable order, every file. |
| VII | Parallel things look parallel | `symmetry` | create/update/delete handlers have identical structure. No "local shortcuts." |
| VIII | One problem, one pattern | `one-pattern-one-way` | You used a helper in module A? You use a helper everywhere. |
| IX | Every literal has a name | `magic-value-elimination` | No inline `"pending"`, no unexplained `86400`. Named constants or it doesn't ship. |
| X | Dead code is noise | `dead-code-intolerance` | Commented-out code, unused imports, TODO comments — delete. Git remembers. |
| XI | Whitespace is punctuation | `visual-rhythm` | Blank lines separate ideas. Consistent spacing. Code is prose. |

## Project Guidelines

| Skill | What It Covers |
|-------|----------------|
| `guidelines-compliance` | Scans all CLAUDE.md files in a repo, builds the inheritance hierarchy, checks code against the project's own documented rules, detects stale guidelines and conflicts between levels |

## Language Packs

| Pack | Skill | What It Covers |
|------|-------|----------------|
| Python | `python-pedantry` | `str \| None` not `Optional`, Pydantic settings, StrEnum, exception chaining, Google docstrings, ruff |
| TypeScript | `typescript-pedantry` | strict tsconfig, discriminated unions, Zod schemas, barrel exports, `as const`, ESLint strict |
| Go | `go-pedantry` | error wrapping with `%w`, interface design, package naming, struct ordering, `golangci-lint` |

## Installation

### Claude Code (via fractional-cto Marketplace)

```bash
# Register the marketplace (once)
/plugin marketplace add oborchers/fractional-cto

# Install the plugin
/plugin install pedantic-coder@fractional-cto
```

### Local Development

```bash
# Test directly with plugin-dir flag
claude --plugin-dir /path/to/fractional-cto/pedantic-coder
```

## Components

### Skills (16)

One meta-skill (`using-pedantic-principles`) that provides the index, 11 universal principle skills, 1 guidelines compliance skill, and 3 language pack skills. Each skill includes:

- Non-negotiable rules with sharp, opinionated guidance
- Good/bad examples across multiple languages
- Actionable review checklists

### Commands (3)

- `/pedantic-coder:pedantic-review` — Review the current code against all relevant pedantic principles with severity-rated findings
- `/pedantic-coder:pedantic-audit` — Audit an entire repository: discovers structure, samples files, identifies codebase-wide convention conflicts
- `/pedantic-coder:guidelines-review` — Scan all CLAUDE.md files in the repo, build the inheritance chain, and check code compliance against the project's own rules

### Agent (1)

- `pedantic-reviewer` — Comprehensive pedantry audit agent that evaluates code against all principles with a pedantry score (pristine → catastrophic)

### Hook (1)

- `SessionStart` — Injects the skill index at the start of every session so Claude knows the principles are available

## The Three Meta-Principles

All principles rest on three foundations:

1. **Consistency is non-negotiable** — One way. Everywhere. Always. A codebase that mixes conventions is a codebase that nobody trusts.

2. **If it looks wrong, it is wrong** — Visual disorder signals logical disorder. Code that is hard to scan is hard to maintain.

3. **Every detail is a decision** — Nothing is "just a style choice." Every abbreviation, every import order, every blank line either reinforces or undermines the codebase's integrity.

## License

MIT
