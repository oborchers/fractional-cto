# planning-tools

Manage Claude Code's plan-mode artifacts and author multi-phase **master planning documents** in your project.

The plugin covers two workflows that complement each other:

1. **Per-session plan-file management** — clean up `~/.claude/plans/<slug>.md` between phases.
2. **Master-plan authoring** — draft, verify, and iterate on long multi-phase planning documents that live in your project repo.

## Commands

### `/planning-tools:plan-context [topic | path] [--domains a,b,c]`

Pre-load context for a future master plan. Four stages:

1. **Stage 1 Triage** — main conversation reads the source artifact and dir-scans likely context locations (`context/`, `docs/`, project root) to propose a non-overlapping domain partition.
2. **Stage 2 Confirm** — main conversation prints the proposed N domains as a plain-text numbered list, then asks a **binary** `AskUserQuestion`: `Proceed with all N domains` / `Cancel — I'll re-run with --domains`. Binary (never multi-select) because `AskUserQuestion` has a hard 4-option cap that would crash on typical 5–10-domain partitions. To customize, the user cancels and re-runs with `--domains a,b,c`. Skipped if `--domains` was supplied or Triage yielded only one domain.
3. **Stage 3 Parallel Explore** — dispatches `plan-context-worker` agents (one per confirmed domain) in a single message. Each returns its findings as its final message; the main conversation persists them to `/tmp/plan-context/<topic-slug>/<domain>.md` (writing any a worker didn't persist itself).
4. **Stage 4 Verify** — main conversation directly reads 3–6 critical files each worker cited, confirms patterns hold, flags any deltas.

Emits a structured **scope report** (key locations, constraints, suggested phase split). **No plan file is written.**

### `/planning-tools:plan-master <topic> [--context <report-path>] [--domains a,b,c]`

Draft a multi-phase master planning document.

- If `--context <path>` is supplied, reuse the worker findings from a prior `/planning-tools:plan-context` run and skip the discovery pre-flight.
- Otherwise, run the same Triage + Confirm + Parallel Explore + Verify pre-flight internally.
- Then dispatches `plan-master-architect` (opus) to synthesize the multi-phase plan in the user's standard template.
- Writes to a project-local path. The plugin tries `context/tickets/`, then `docs/plans/`, then `.claude/plans/master/`, asking via `AskUserQuestion` if none exist.

The architect composes the **universal core** sections (Title, plan-level **TL;DR**, Context block, Open Questions, Implementation Phases, Design Principles, Out of Scope) plus **trigger-based optional sections** (Schema + Rollback for data work; Component Architecture + UI States for UI work; Cost + Risks for ops; Recovery + Schema for incidents; etc.). Phases are numbered with **integers only** (`1, 2, 3, …`).

### `/planning-tools:plan-open-questions [path] [question-number]`

Walk through a master plan's `## Open Questions` one by one, capturing the user's choice for each via `AskUserQuestion`, then batch-apply all resolutions to the plan.

For each open question, the command (running in the **main conversation** — no subagent dispatch):

1. Reads cited evidence files (`path:line` refs, ADRs, ticket IDs) to ground the analysis.
2. Composes a context block: question header → 1–2 context paragraphs → optional "Why X / Why it could matter / Risk profile" sub-analysis → 2–4 numbered alternatives.
3. Marks one alternative as **Recommended** when an obvious best answer exists; always includes a **Defer — keep open** path.
4. Calls `AskUserQuestion` with the 2–4 alternatives (capped at 4 per the schema).
5. Captures the choice in memory.

After all questions are walked, presents a batch summary and a 3-option apply gate (`Apply / Show diff first / Discard`). On Apply, moves answered questions from `## Open Questions` to `## Resolved Questions`. Deferred questions stay in Open.

Supports both v0.3.0 list shape and v0.2.x legacy table shape (transition note printed when the legacy parser fires).

Optional `[question-number]` argument targets a single question — useful for re-running on just one Q after a partial answer.

### `/planning-tools:plan-verify <path>`

Audit a drafted master plan against the `plan-verification-checklist` skill. Dispatches the `plan-verifier` agent, which checks:

- Universal-core completeness
- Trigger-based section-coverage gaps
- Phase actionability (file paths, exit criteria, tests)
- **Integer phase numbering** (any decimal, letter, range, or sub-phase = Critical)
- Dependency traceability (artifact-level specificity required)
- Citation resolution
- Callout / evidence convention compliance
- Open Questions placement (immediately after context block)

Emits Critical / Important / Suggestion findings with `path:line` references and a PASS / FAIL verdict. On PASS, optionally appends a `- **Verified:** YYYY-MM-DD` bullet to the plan's context block (a `> **Verified:**` line on legacy blockquote plans), with explicit user approval via `AskUserQuestion`.

### `/planning-tools:plan-tick [phase-number] [path]`

**Auto mode (no args):** detect the current branch, find the master plan that matches it (by filename → branch-name substring), then in the **main conversation** walk each unticked phase against the working tree + branch diff vs the merge-base (file existence + diff membership + symbol presence + checkbox state) and tick every phase the audit verdicts `ACHIEVED`. Conservative — `UNCERTAIN` and `NOT_ACHIEVED` phases stay unticked. No subagent is dispatched.

**Manual override:** `/planning-tools:plan-tick <phase>` ticks the named phase explicitly without invoking the auditor. Use this when the auditor under-judges (e.g., non-code phases like documentation or planning) or when you know better than the audit.

Both modes are **non-interactive** — the command never calls `AskUserQuestion`. If something cannot be resolved deterministically (e.g., not in a git repo, no master plans found, malformed plan), it errors with a clear message.

**Plan discovery in auto mode:**
1. Glob candidates under `context/tickets/`, `docs/plans/`, `.claude/plans/master/` (relative to git root).
2. If exactly one candidate exists → use it.
3. If multiple → pick the one whose normalized basename appears in the normalized current branch name (case + separator insensitive).
4. If multiple match → pick the most-recently-modified among the matches.
5. If no match → fall back to the most-recently-modified candidate overall.

Works on plans conforming to `planning-tools:master-plan-methodology` v0.3.0+ (heading + checklist shape) and on legacy v0.2.x table-shape plans (transition window). Shape detection is automatic — non-conforming plans get a clear error pointing at the methodology skill.

### `/planning-tools:plan-progress [--final] [--destination <type>:<id>] [--style-from <path>] [--ticket <id>]`

Synthesize a single dense progress entry for the current branch and append/update it at the configured destination. Reuses the same branch-matching + plan resolution as `/planning-tools:plan-tick`. SHA-based idempotency means safe to re-run between phases — only new commits drive new prose; already-cited SHAs in the existing entry are preserved verbatim.

**Destinations (v1):**

- `markdown` — a project-local markdown file at any path the user chooses (e.g., `PROGRESS.md` at root, `docs/PROGRESS.md`, `context/PROGRESS.md`, or wherever this project conventionally keeps progress logs). Entries are prepended (newest-first).
- `linear` — comment on a Linear ticket (via `mcp__linear-server__save_comment`). Identifier: ticket ID like `AIA-1234`.
- `github` — comment on a GitHub issue or PR (via `gh` CLI). Identifier: `<owner>/<repo>#<number>`.

**No path is assumed.** First-run selection probes the repo for an existing `PROGRESS.md` / `CHANGELOG.md` / `CHANGES.md` file. If one is found, it is offered as the recommended option in a **binary `AskUserQuestion`** (Use `<discovered-path>` / Cancel — re-run with `--destination`). If none is found, the recommended option is Cancel — the user supplies a path via `--destination markdown:<path>` so the plugin never fabricates a default location. The choice persists to `.claude/planning-tools.local.md`; override per-call with `--destination <type>:<id>` without overwriting the saved setting.

**Three-way entry detection:**

- No existing entry → synthesize a new one.
- Existing entry without `✅` → in-flight update; the synthesizer extends in place, preserving prior SHA citations.
- Existing entry with `✅` → 3-option `AskUserQuestion`: refresh / new entry / cancel.

**`--final` flag:** prepends `**Shipped <today> via PR #<N>.**` (PR number resolved via `gh pr list --head <branch>` when available) and appends `✅` to the heading.

For the canonical style spec, sub-markers (`Piggybacked:`, `Verification:`, `Out of scope:`), entry-key marker convention, SHA-tracking algorithm, and the source/destination adapter contracts, see the `planning-tools:progress-methodology` skill.

### `/planning-tools:plan-delete`

Clear the current session's plan file at `~/.claude/plans/<slug>.md`. Detects this session's slug by grepping the transcript at `~/.claude/projects/<encoded-cwd>/$CLAUDE_CODE_SESSION_ID.jsonl` — never relies on file mtime (which breaks with parallel sessions). Deletes the file, recreates it empty, re-reads it so the session is primed for the next plan-mode entry. Bootstraps via `EnterPlanMode` → no-op placeholder → `ExitPlanMode` if plan mode has never been entered.

## The 8-step Master Plan Workflow

```
1. /planning-tools:plan-context           → scope report (no plan written)
2. /planning-tools:plan-master            → multi-phase plan drafted to project-local path
3. /planning-tools:plan-open-questions    → walk through Open Questions; batch-apply to Resolved
4. /planning-tools:plan-verify            → Critical/Important/Suggestion findings + PASS/FAIL
5. Manual phase loop       → copy phase into built-in /plan, execute
6. /planning-tools:plan-tick              → auto-tick provenly-achieved phases ✅ in the master plan
7. /planning-tools:plan-progress          → append/update progress entry at configured destination (markdown / Linear / GitHub)
8. /planning-tools:plan-delete            → clear per-session plan file, loop back to step 5
```

## Ticket-aware planning

`/planning-tools:plan-master` and `/planning-tools:plan-context` accept ticket URLs or IDs as their first argument. When matched, the plugin fetches the ticket via the source adapter — title, body, and **all comments, no cap** — and injects the block into Stage 1 Triage + every Stage 3 worker prompt. The architect uses the ticket for the Context block's Evidence bullet, propagates unresolved comment-thread questions into Open Questions, and emits a `- **Ticket:** <url>` bullet as the first context bullet.

Supported ticket sources (v1): Linear (via `mcp__linear-server__*`) and GitHub (via `gh` CLI). Free-text topics still work — pattern detection runs first; on no match, existing behavior is preserved.

## Configuration

Per-project progress settings live at `.claude/planning-tools.local.md` (project-relative, **should be gitignored**). YAML frontmatter + markdown body, per the `plugin-dev:plugin-settings` pattern:

```yaml
---
progress_destination: markdown            # or "linear" or "github"
progress_destination_id: <your-progress-path>  # for markdown, a path you choose (e.g., PROGRESS.md, docs/PROGRESS.md, context/PROGRESS.md); for linear/github, a ticket/issue ref
ticket_provider: linear                   # or "github" or "none"
ticket_prefix: AIA                        # optional anchor for Linear ID auto-detection from branch names
---

# planning-tools settings

Free-form notes about this project's progress conventions, if any.
```

`/planning-tools:plan-progress` writes this file the first time the user picks a destination. To switch destinations later, edit the file directly or pass `--destination <type>:<id>` for a one-off override.

Add to `.gitignore`:

```gitignore
.claude/*.local.md
```

## Master-Plan Conventions

Codified in the `master-plan-methodology` skill. Highlights:

- **Integer phase numbering only** — `1, 2, 3, …`. No `0.5`, `1A`, `Phase A`, ranges, or sub-phases. The word "Phase" is reserved for these integer-numbered work units inside a master plan; workflow steps and internal command stages use "Stage" or "step" instead.
- **No sizing estimates** — XS/S/M/L, T-shirt sizes, time estimates are not used. Phases describe scope, not effort.
- **Open Questions at the top** — placed immediately after the context block, not at the end. Blockers must be visible to anyone skimming the first 30 lines.
- **Project-agnostic** — no ticket-prefix or plan-type taxonomy. Optional sections are added based on what the work touches, derived from worker findings.
- **Authoring shape (v0.3.0+, plain bullets v0.3.2+)** — phases are `### Phase <N>: <verb-led name> <emoji>` H3 headings with `- ` bulleted scope items underneath (plain bullets — no `- [ ]` checkboxes; the phase heading emoji is the sole tick signal). Open Questions and Resolved Questions are bulleted `- **Q<N> — <question>:** ...` lines. **No markdown tables for any of these three sections** — wide-cell tables in markdown become unreadable. Narrow-cell tables elsewhere (Architecture, Data Model, file × phase matrix, etc.) are still allowed. Legacy v0.3.0/0.3.1 plans with `- [ ]` / `- [x]` keep parsing — the optional `[ ]`/`[x]` prefix is stripped silently.
- **Per-phase TL;DR (v0.3.1+)** — each phase has a `**TL;DR:** <1–3 sentences>` line under the heading, before scope items. First sentence = what the phase does, subsequent sentence(s) = why. Lets readers scan the plan top-to-bottom reading only TL;DR lines to grasp every phase in 60 seconds. The verifier flags missing TL;DRs as Important.
- **Status emoji** — `⏳ 🚧 ✅ ❌` as the last token of each phase heading.
- **Evidence attribution** — every claim cites source (transcript+date+speaker, ADR-NN, `path:line`).
- **Callout labels** — bold-prefix `**Decision:**`, `**Rationale:**`, `**Risk:**`, `**Mitigation:**`, `**Note:**`.

### Tiny worked example

```markdown
## Implementation Phases

### Phase 1: Add invalid_session discriminator to requireAuth 401s ⏳

**TL;DR:** Stamp `code: 'invalid_session'` on every `requireAuth` 401 response so the frontend can discriminate genuine session expiry from upstream-relayed 401s. Needed because the current discriminator is bare HTTP status, which conflates auth-gate failures with EPOS/SF upstream rejection.

- Widen `ProblemDetails.status` to `401 | 404 | 503` at `_shared/problem-response.ts:32`
- Replace 3 `corsError(string, 401)` paths in `_shared/auth.ts:82-128` with `problemResponse({ status: 401, code: 'invalid_session', ... })`
- **Tests:** `_shared/auth.test.ts` — assert all 3 paths emit Content-Type `application/problem+json`
- **Exit criteria:** `make test-functions` green; local curl returns 401 + problem+json + `code: invalid_session`

### Phase 2: Add code-match safety net to session-errors.ts ✅

**TL;DR:** Add positive `code === 'session_expired' | 'invalid_session' | 'PGRST302'` branches to `shouldInvalidateSession` before removing the bare-401 fallback in Phase 4. Lands the safety net first so real session expiry continues to fire when Phase 4 removes the broad branch.

- Add `error.code === 'session_expired' || 'invalid_session'` branches to `shouldInvalidateSession` at `:175`
- Add `error.code === 'PGRST302'` branch (closes JWT-malformed gap)
- **Tests:** `session-errors.test.ts` — 3 positive fixtures
- **Exit criteria:** `make test` green; bare-401 branch unchanged (Phase 4 removes it)
```

## How Per-Session Plan File Detection Works

Plan files live globally in `~/.claude/plans/`, but each session has its own slug. Claude Code stamps every transcript entry with a top-level `"slug"` field once plan mode is entered — this is the authoritative source:

| Source | Value |
|--------|-------|
| Session UUID | `$CLAUDE_CODE_SESSION_ID` (env var, set by Claude Code) |
| Transcript | `find ~/.claude/projects -name "${SESSION_ID}.jsonl"` |
| Slug extraction | `grep -m1 -o '"slug":"[^"]*"' <transcript> \| sed 's/"slug":"//; s/"$//'` |
| Plan file | `~/.claude/plans/<slug>.md` |

If no slug is present in the transcript, plan mode has not been entered this session — `/planning-tools:plan-delete` bootstraps with `EnterPlanMode` → no-op plan → `ExitPlanMode` to allocate one, then re-extracts.

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
