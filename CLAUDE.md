# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**fractional-cto** is a Claude Code plugin marketplace containing opinionated, research-backed plugins for software engineering. It is purely markdown/JSON/bash — no build system, no runtime dependencies, no tests to run.

## Local Development

```bash
# Test a plugin locally
claude --plugin-dir /path/to/fractional-cto/<plugin-name>
```

There is no build step, linter, or test suite. Validation is manual: start a Claude session with the plugin and verify hooks fire, skills invoke, and commands work.

## Architecture

### Marketplace Registry

`.claude-plugin/marketplace.json` is the central registry listing all available plugins. Each plugin lives in its own top-level directory.

### Plugin Structure

```
<plugin-name>/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, keywords)
├── README.md                    # Plugin docs and principle overview
├── hooks/
│   ├── hooks.json               # Registers SessionStart hook
│   └── session-start.sh         # Injects meta-skill index into session context
├── commands/
│   └── <name>-review.md         # Manual review command
├── agents/
│   └── <name>-reviewer.md       # Comprehensive audit agent (model: sonnet)
└── skills/
    ├── using-<name>-principles/ # Meta-skill: index of all principle skills
    └── <principle-name>/        # Individual principle skills, each with:
        ├── SKILL.md             #   Principles, checklists, good/bad patterns
        └── examples/            #   Code examples relevant to the domain
```

### Activation Flow

1. **SessionStart hook** (`hooks/hooks.json` → `hooks/session-start.sh`) fires on startup/resume/clear/compact
2. `session-start.sh` reads the meta-skill (`using-*-principles/SKILL.md`), escapes it, and outputs JSON with `additional_context`
3. Claude now knows the available principle skills and when to invoke each
4. Skills are invoked automatically when Claude detects relevant work, or manually via the plugin's review command

### Key Design Decisions

- **Skills are YAML-frontmattered markdown** with `name`, `description`, and `version` fields
- **Commands use `disable-model-invocation: true`** — they guide Claude to invoke skills, not execute code
- **Agents specify `model: sonnet`** and include severity guides (Critical/Important/Suggestion)
- **`session-start.sh` uses `${CLAUDE_PLUGIN_ROOT}`** to resolve paths relative to the plugin root
- **Examples are domain-appropriate** — each plugin uses languages and frameworks relevant to its domain

## Adding a New Plugin

1. Create a new top-level directory following the plugin structure above
2. Add principle skills + 1 meta-skill index (skill count varies by plugin)
3. Create a review command, reviewer agent, and SessionStart hook
4. Register the plugin in `.claude-plugin/marketplace.json`

## Adding a New Skill to an Existing Plugin

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`, `version`)
2. Add examples in `skills/<skill-name>/examples/` if applicable
3. Update the meta-skill index (`skills/using-*-principles/SKILL.md`) to include the new skill
4. Update the agent and command markdown to reference the new skill
5. Update the plugin `README.md`

## Conventions

- Skill directory names use kebab-case
- SKILL.md files include review checklists and good/bad pattern comparisons
- Principles cite real-world sources and industry research
- Meta-principles anchor each plugin (documented in the meta-skill and README)
- **Use `AskUserQuestion` for every user decision point** in commands and agents. Never fall back to inline text prompts like "Approve?" or listing options in prose. The interactive selector provides a consistent, navigable UX. Open-ended free-text questions (backstory, detailed feedback) are exempt.
- **Version bumps must update both files:** `.claude-plugin/plugin.json` (the plugin's own manifest) and `.claude-plugin/marketplace.json` (the central registry). These must always stay in sync.

## Single-Owner Rule for Skill Content

Every concept, rule, or guideline must have exactly **one owner skill** that fully defines it. Other skills that touch the same concept must cross-reference the owner rather than restating or duplicating the content.

**Why:** When a rule appears in multiple skills, values drift (e.g., one says "5 shadow levels," another says "<=4"), scales diverge, and updates require synchronized edits across files. Single ownership eliminates contradictions and makes maintenance tractable.

**How to apply:**
1. Each measurable rule (e.g., "WCAG 4.5:1 contrast") lives in one skill with full explanation
2. Other skills that need the rule reference the owner: "Apply WCAG contrast ratios (see `accessibility-inclusive-design` skill)"
3. The meta-skill index and review checklists may summarize rules, but detailed definitions stay in the owner
4. When adding new content, check existing skills first — if a concept already has an owner, cross-reference it
