# planning-tools

Manage Claude Code's plan-mode artifacts and author multi-phase **master planning documents** in your project.

The plugin covers two workflows that complement each other:

1. **Per-session plan-file management** — clean up `~/.claude/plans/<slug>.md` between phases.
2. **Master-plan authoring** — draft, verify, and iterate on long multi-phase planning documents that live in your project repo.

## Commands

### `/plan-context [topic | path] [--domains a,b,c]`

Pre-load context for a future master plan. Four stages:

1. **Stage 1 Triage** — main conversation reads the source artifact and dir-scans likely context locations (`context/`, `docs/`, project root) to propose a non-overlapping domain partition.
2. **Stage 2 Confirm** — the proposal goes through `AskUserQuestion` (multi-select). User adds, removes, or edits the domain list. Skipped if `--domains` was supplied.
3. **Stage 3 Parallel Explore** — dispatches `plan-context-worker` agents (one per confirmed domain) in a single message. Each writes intermediate findings to `/tmp/plan-context/<topic-slug>/<domain>.md`.
4. **Stage 4 Verify** — main conversation directly reads 3–6 critical files each worker cited, confirms patterns hold, flags any deltas.

Emits a structured **scope report** (key locations, constraints, suggested phase split). **No plan file is written.**

### `/plan-master <topic> [--context <report-path>] [--domains a,b,c]`

Draft a multi-phase master planning document.

- If `--context <path>` is supplied, reuse the worker findings from a prior `/plan-context` run and skip the discovery pre-flight.
- Otherwise, run the same Triage + Confirm + Parallel Explore + Verify pre-flight internally.
- Then dispatches `plan-master-architect` (opus) to synthesize the multi-phase plan in the user's standard template.
- Writes to a project-local path. The plugin tries `context/tickets/`, then `docs/plans/`, then `.claude/plans/master/`, asking via `AskUserQuestion` if none exist.

The architect composes the **universal core** sections (Title, Context block, Open Questions, Implementation Phases, Design Principles, Out of Scope) plus **trigger-based optional sections** (Schema + Rollback for data work; Component Architecture + UI States for UI work; Cost + Risks for ops; Recovery + Schema for incidents; etc.). Phases are numbered with **integers only** (`1, 2, 3, …`).

### `/plan-verify <path>`

Audit a drafted master plan against the `plan-verification-checklist` skill. Dispatches the `plan-verifier` agent, which checks:

- Universal-core completeness
- Trigger-based section-coverage gaps
- Phase actionability (file paths, exit criteria, tests)
- **Integer phase numbering** (any decimal, letter, range, or sub-phase = Critical)
- Dependency traceability (artifact-level specificity required)
- Citation resolution
- Callout / evidence convention compliance
- Open Questions placement (immediately after context block)

Emits Critical / Important / Suggestion findings with `path:line` references and a PASS / FAIL verdict. On PASS, optionally appends `> **Verified:** YYYY-MM-DD` to the plan's context block (with explicit user approval via `AskUserQuestion`).

### `/plan-delete`

Clear the current session's plan file at `~/.claude/plans/<slug>.md`. Detects this session's slug by grepping the transcript at `~/.claude/projects/<encoded-cwd>/$CLAUDE_CODE_SESSION_ID.jsonl` — never relies on file mtime (which breaks with parallel sessions). Deletes the file, recreates it empty, re-reads it so the session is primed for the next plan-mode entry. Bootstraps via `EnterPlanMode` → no-op placeholder → `ExitPlanMode` if plan mode has never been entered.

## The 5-step Master Plan Workflow

```
1. /plan-context         → scope report (no plan written)
2. /plan-master          → multi-phase plan drafted to project-local path
3. /plan-verify          → Critical/Important/Suggestion findings + PASS/FAIL
4. Manual phase loop     → copy phase into built-in /plan, execute, tick row
5. /plan-delete          → clear per-session plan file, loop back to step 4
```

## Master-Plan Conventions

Codified in the `master-plan-methodology` skill. Highlights:

- **Integer phase numbering only** — `1, 2, 3, …`. No `0.5`, `1A`, `Phase A`, ranges, or sub-phases. The word "Phase" is reserved for these integer-numbered work units inside a master plan; workflow steps and internal command stages use "Stage" or "step" instead.
- **No sizing estimates** — XS/S/M/L, T-shirt sizes, time estimates are not used. Phases describe scope, not effort.
- **Open Questions at the top** — placed immediately after the context block, not at the end. Blockers must be visible to anyone skimming the first 30 lines.
- **Project-agnostic** — no ticket-prefix or plan-type taxonomy. Optional sections are added based on what the work touches, derived from worker findings.
- **Status column** — `⏳ 🚧 ✅ ❌` emoji in the Implementation Phases table.
- **Evidence attribution** — every claim cites source (transcript+date+speaker, ADR-NN, `path:line`).
- **Callout labels** — bold-prefix `**Decision:**`, `**Rationale:**`, `**Risk:**`, `**Mitigation:**`, `**Note:**`.

## How Per-Session Plan File Detection Works

Plan files live globally in `~/.claude/plans/`, but each session has its own slug. Claude Code stamps every transcript entry with a top-level `"slug"` field once plan mode is entered — this is the authoritative source:

| Source | Value |
|--------|-------|
| Session UUID | `$CLAUDE_CODE_SESSION_ID` (env var, set by Claude Code) |
| Transcript | `find ~/.claude/projects -name "${SESSION_ID}.jsonl"` |
| Slug extraction | `grep -m1 -o '"slug":"[^"]*"' <transcript> \| sed 's/"slug":"//; s/"$//'` |
| Plan file | `~/.claude/plans/<slug>.md` |

If no slug is present in the transcript, plan mode has not been entered this session — `/plan-delete` bootstraps with `EnterPlanMode` → no-op plan → `ExitPlanMode` to allocate one, then re-extracts.

## Installation

This plugin ships as part of the `fractional-cto` marketplace.

```bash
/plugin install planning-tools@fractional-cto
```

Or test locally:

```bash
claude --plugin-dir /path/to/fractional-cto/planning-tools
```

## License

MIT
