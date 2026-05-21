---
name: using-planning-tools
description: "This skill should be used when the user invokes any /plan-* command from the planning-tools plugin (/plan-context, /plan-master, /plan-open-questions, /plan-verify, /plan-tick, /plan-progress, /plan-delete), asks how Claude Code's plan files work, asks where plans are stored, asks to author or audit a multi-phase master planning document, asks how to walk through a plan's Open Questions interactively, asks how to write progress entries, or mentions ~/.claude/plans/ or .claude/planning-tools.local.md. Provides the index of planning-tools commands, the master-plan workflow lifecycle, the v0.3.0+ list-shape mandate (phases and questions as headings + to-do checklists, never tables), the progress-entry methodology, and the mechanics of Claude Code's plan-mode file storage."
version: 0.7.1
---

# Planning Tools

This plugin provides two complementary workflows on top of Claude Code's plan mode:

1. **Per-session plan-file management** — Claude Code stores each session's plan at `~/.claude/plans/<slug>.md`. The plugin's `/planning-tools:plan-delete` command cleans these up.
2. **Master-plan authoring** — long, multi-phase planning documents that live in the user's project (e.g., `context/tickets/`, `docs/plans/`) and decompose work into actionable phases. The plugin's `/planning-tools:plan-context`, `/planning-tools:plan-master`, and `/planning-tools:plan-verify` commands cover this lifecycle.

## How to Access Skills

Use the `Skill` tool to invoke any skill by name. When invoked, follow the skill's guidance directly.

## Commands

| Command | Triggers On |
|---------|-------------|
| `/planning-tools:plan-context [topic] [--domains a,b,c]` | Pre-loading context for a future master plan. Stage 1 Triage proposes domains, Stage 2 Confirm prints them as text + asks a **binary** `AskUserQuestion` (Proceed / Cancel — never multi-select, since the 4-option cap would crash on common N≥5), Stage 3 dispatches parallel `plan-context-worker` agents (one per domain), Stage 4 verifies findings with direct Reads. Emits a scope report. NO plan file written. |
| `/planning-tools:plan-master <topic> [--context <path>] [--domains a,b,c]` | Drafting a multi-phase master plan. Reuses a prior `/planning-tools:plan-context` report if `--context` is supplied; otherwise runs the same Triage + Confirm + Explore + Verify pre-flight (Stage 2 uses the same binary-confirm pattern). Then dispatches `plan-master-architect` (opus) to synthesize. Writes to a project-local path (`context/tickets/`, `docs/plans/`, or `.claude/plans/master/`). |
| `/planning-tools:plan-open-questions [path] [question-number]` | Walking through a master plan's Open Questions interactively. Resolves plan via branch-match (lifted from plan-tick). For each open question, the main conversation reads cited evidence files, composes a context block (question header → 1–2 context paragraphs → "Why X / Why it could matter / Risk profile" sub-analysis → 2–4 alternatives with one Recommended + one Defer), then calls `AskUserQuestion`. Accumulates choices in memory; presents a batch summary and 3-option apply gate (Apply / Show diff first / Discard). On Apply: moves answered questions from `## Open Questions` to `## Resolved Questions`. Deferred questions stay in Open. Runs entirely in the main conversation — no subagent dispatch. Dual-shape support (v0.3.0 list shape primary, v0.2.x table shape with transition note). |
| `/planning-tools:plan-verify [path]` | Auditing a drafted master plan. If no path is supplied, globs candidates and uses binary-confirm (Proceed with most-recent / Cancel) to pick. Dispatches `plan-verifier` agent against the `plan-verification-checklist` skill. Emits Critical/Important/Suggestion findings with a PASS/FAIL verdict. On PASS, optionally appends `> **Verified:** YYYY-MM-DD` to the plan's context block. |
| `/planning-tools:plan-tick [phase] [path]` | Auto-ticking provenly-achieved phases in a master plan. **Default (no args):** detects the current branch, resolves the master plan that matches it, runs the audit inline in the main conversation (file existence + branch diff membership + symbol presence + checkbox state), ticks all phases verdicted `ACHIEVED`. **Manual override** `/planning-tools:plan-tick <phase>`: ticks one phase without audit. Both modes are non-interactive — never asks. No subagent dispatched. Works only on plans conforming to `planning-tools:master-plan-methodology` v0.2.1+. |
| `/planning-tools:plan-progress [--final] [--destination <type>:<id>] [--style-from <path>] [--ticket <id>]` | Synthesizing a single dense progress entry for the current branch and applying it at the configured destination (markdown file / Linear comment / GitHub issue/PR comment). Reuses plan-tick's branch + plan resolution. SHA-based idempotency: safe to re-run between phases. Three-way detection on the existing entry: new / in-flight update / completed (3-option refresh prompt). First-run destination selection persists to `.claude/planning-tools.local.md`. `--final` flips to shipped state with `**Shipped <date> via PR #<N>.**` + `✅` heading. Composition runs inline in the main conversation — no subagent dispatched. Style spec, sub-markers, and adapter contracts in `planning-tools:progress-methodology`. |
| `/planning-tools:plan-delete` | Clearing the current session's plan file at `~/.claude/plans/<slug>.md`. Detects the slug via `$CLAUDE_CODE_SESSION_ID` + transcript grep, deletes the file, recreates empty, re-reads. Bootstraps with `EnterPlanMode` → no-op plan → `ExitPlanMode` if the session has never entered plan mode. |

## The 8-step Master Plan Workflow

```
┌───────────────────────────────────────────────────────────────────┐
│  1. /planning-tools:plan-context [topic] [--domains a,b,c]        │
│     Stage 0 (optional ticket-fetch) → Stage 1 Triage → Stage 2    │
│     Confirm → Stage 3 Parallel Explore → Stage 4 Verify. Emits a  │
│     scope report. No plan file written.                           │
├───────────────────────────────────────────────────────────────────┤
│  2. /planning-tools:plan-master <topic> [--context <report-path>] │
│     Reuses /plan-context report (if --context) or runs the same   │
│     pre-flight. Auto-fetches ticket title + body + all comments   │
│     if topic matches a Linear/GitHub pattern. Dispatches          │
│     plan-master-architect (opus). Writes to a project-local path. │
├───────────────────────────────────────────────────────────────────┤
│  3. /planning-tools:plan-open-questions [path] [Q-number]         │
│     Walk through each Open Question one by one. Main conversation │
│     reads cited evidence + composes context block with 2–4        │
│     alternatives (one Recommended + one Defer). AskUserQuestion   │
│     captures the choice. Batch apply moves answered questions     │
│     from Open to Resolved. No subagent dispatch.                  │
├───────────────────────────────────────────────────────────────────┤
│  4. /planning-tools:plan-verify <path>                            │
│     Audits the drafted plan. Critical/Important/Suggestion        │
│     findings + PASS/FAIL verdict. Optional Verified callout.      │
├───────────────────────────────────────────────────────────────────┤
│  5. Manual phase iteration (built-in /plan)                       │
│     User copies the next unticked phase from the master plan into │
│     Claude Code's built-in /plan. Plan mode produces the per-     │
│     phase plan at ~/.claude/plans/<slug>.md. User executes.       │
├───────────────────────────────────────────────────────────────────┤
│  6. /planning-tools:plan-tick                                     │
│     Auto-tick: branch-matched plan + auditor-verdicted ACHIEVED   │
│     phases get ✅. Conservative. Manual override: /plan-tick <n>. │
├───────────────────────────────────────────────────────────────────┤
│  7. /planning-tools:plan-progress [--final]                       │
│     Synthesize one dense entry per branch; append/update at the   │
│     configured destination (markdown / Linear / GitHub). SHA-     │
│     based idempotency, three-way entry detection, --final ships.  │
├───────────────────────────────────────────────────────────────────┤
│  8. /planning-tools:plan-delete                                   │
│     Clears the per-session plan file. Loop back to step 5.        │
└───────────────────────────────────────────────────────────────────┘
```

## Ticket-aware planning

`/planning-tools:plan-master` and `/planning-tools:plan-context` accept a ticket URL or ID as their first argument. When matched (Linear `[A-Z]{2,6}-\d+` or `https://linear.app/...`; GitHub `https://github.com/<owner>/<repo>/issues/<N>` or `<owner>/<repo>#<N>`), the plugin fetches the ticket via the source adapter — title, body, and **all comments, no cap** — and propagates the block to Stage 1 Triage + every Stage 3 worker + the architect. The architect prepends `> **Ticket:** <url>` above the Context block. Free-text topics still work — on no pattern match, existing behavior is preserved. See `planning-tools:progress-methodology` for the adapter contract.

## Supporting Skills

| Skill | Purpose |
|---|---|
| `planning-tools:master-plan-methodology` | Codifies the master-plan template: universal core sections, trigger-based optional sections, integer-only phase rule, Open Questions at top, status emoji convention, evidence attribution, callouts, cross-references. Read this before authoring or reviewing any master plan. |
| `planning-tools:plan-verification-checklist` | Single owner of the audit dimensions used by `/planning-tools:plan-verify` and the `plan-verifier` agent. Defines severity (Critical/Important/Suggestion) and the PASS/FAIL verdict rule. |
| `planning-tools:progress-methodology` | Single owner of the progress-entry style (dense paragraph), sub-marker convention (`Piggybacked:` / `Verification:` / `Out of scope:` / `Shipped`), entry-key marker format, SHA-tracking idempotency algorithm, three-way detection rule, comment-fetch policy (all comments, no cap), and the source + destination adapter contracts (markdown / Linear / GitHub). Read this when running or maintaining `/planning-tools:plan-progress`. |

## How Per-Session Plan File Detection Works

For `/planning-tools:plan-delete`: Claude Code stamps every transcript entry with a top-level `"slug"` field once plan mode is entered. That slug equals the plan filename (without `.md`). This is the authoritative source:

1. Read `$CLAUDE_CODE_SESSION_ID` from the environment (the current session's UUID).
2. Compute the transcript path: `$HOME/.claude/projects/<encoded-cwd>/$CLAUDE_CODE_SESSION_ID.jsonl`
   - The encoded CWD replaces both `/` and `.` with `-` (e.g., `/Users/o/Code.nosync/x` becomes `-Users-o-Code-nosync-x`).
3. Extract the slug: `grep -m1 -o '"slug":"[^"]*"' <transcript> | sed 's/"slug":"//; s/"$//'`
4. The plan file is `~/.claude/plans/<slug>.md`.

If the grep returns empty, the session has not entered plan mode yet — bootstrap with `EnterPlanMode` → minimal no-op plan → `ExitPlanMode`, then re-extract.

**Why not "most recently modified file in ~/.claude/plans/"?** Parallel sessions in other terminals/projects write to their own slugs concurrently. mtime is unreliable.

**Why not grep the transcript for `~/.claude/plans/<slug>.md` paths?** That matches any plan path mentioned in conversation (e.g., `ls` output), not just the session's true plan slug. The `"slug"` field is set by Claude Code itself and is unambiguous.

## Why This Plugin Exists

- **Per-session plan files persist by design** — they live outside the context window and survive compaction so they can be re-loaded. The downside: stale content accumulates in the slug file across re-plans, and after compaction Claude often loses awareness of the path. `/planning-tools:plan-delete` solves both.
- **Master plans are a different artifact** — they live in the project (git-versioned), describe a topic in depth across multiple phases, and act as the source of truth for execution. The plugin codifies how they are authored (`/planning-tools:plan-context`, `/planning-tools:plan-master`) and audited (`/planning-tools:plan-verify`), with a strict format-driven methodology so plans are predictable and machine-checkable.

## Conventions That Apply Everywhere

- **Integer phase numbering only** — phases are `1, 2, 3, …`. No decimals, no letter suffixes, no sub-phases. The word "Phase" is reserved for integer-numbered work units inside a master plan.
- **List shape for phases and questions (v0.3.0+)** — Implementation Phases is a series of `### Phase <N>: <name> <emoji>` H3 headings with `- [ ]` checklists underneath. Open Questions and Resolved Questions are bulleted `- **Q<N> — <question>:** ...` lines. **No markdown tables for any of these three sections.** `/planning-tools:plan-tick` supports the legacy v0.2.x table shape during a transition window.
- **No sizing estimates** — phases describe scope, not effort. No XS/S/M/L, no time estimates.
- **Open Questions at the top** — blocking questions appear immediately after the context block, not at the end of the plan.
- **Project-agnostic** — the plugin does not assume any ticket-prefix convention. The architect picks optional sections based on what the work touches, not from a classifier.
- **AskUserQuestion is owned by the main conversation** — never by subagents. The plugin's commands handle all user decision points; agents only fetch, synthesize, or audit.
