---
description: "Draft a multi-phase master planning document. Runs Triage + Confirm + Parallel Explore + Verify (or reuses a /plan-context report), then dispatches plan-master-architect to synthesize. Writes to a project-local path."
argument-hint: "<topic> [--context <report-path>] [--domains a,b,c]"
---

You are **drafting a master planning document**. The output is a project-local `.md` file in the user's repository, written by the `plan-master-architect` agent following the `master-plan-methodology` skill.

**Input:** `$ARGUMENTS`

Parse the arguments:
- **Topic** (required) — a ticket ID, ticket URL, file path, or free-form scope statement.
- `--context <path>` (optional) — path to a scratch directory from a prior `/planning-tools:plan-context` run (containing per-domain worker findings). If supplied, **skip the discovery pre-flight** and go straight to synthesis.
- `--domains a,b,c` (optional) — pre-seed the domain partition (skips Stage 2 Confirm).

If arguments are empty, ask the user for a topic via `AskUserQuestion` before proceeding.

### Ticket-source detection (Step 0)

Before treating the topic as free-text, run pattern detection against the first argument. If it matches one of these forms, **fetch the ticket source** via the adapter contract codified in `planning-tools:progress-methodology`:

| Pattern | Provider |
|---|---|
| `^[A-Z]{2,6}-\d+$` (e.g., `AIA-1234`, `CI-21`) | Linear |
| `^https://linear\.app/.+/issue/([A-Z]{2,6}-\d+)/` | Linear |
| `^https://github\.com/([^/]+)/([^/]+)/(issues\|pull)/(\d+)` | GitHub |
| `^([^/\s]+/[^/\s]+)#(\d+)$` (e.g., `org/repo#42`) | GitHub |

On a match:

1. **Fetch** title, body, and **all comments** (no cap, per the comment-fetch policy in `progress-methodology`):
   - Linear: `mcp__linear-server__get_issue(id)` + `mcp__linear-server__list_comments(issueId)`.
   - GitHub: `gh issue view <N> --repo <owner>/<repo> --json title,body,state,url,comments` (or `gh pr view`).
2. **Treat the fetched `{ title, body, comments[] }` as additional source artifact context** for Stage 1 Triage and propagate it to Stage 3 workers + the architect. The Triage step scans comments for: acceptance criteria, prior decisions, unresolved questions to surface as Open Questions, and recent reroutes that override the body.
3. **Save the ticket URL** on the architect's input so the rendered plan includes a `- **Ticket:** <url>` bullet as the first context bullet (per the `master-plan-methodology` skill).

If the matched provider's MCP/CLI is unavailable, **fail loudly**: e.g., `Linear MCP not loaded — cannot fetch <ticket>. Re-run on a session that has the Linear MCP, or pass the topic as free-form text.` Do not silently degrade.

If no pattern matches → existing free-text behavior (no fetch, no `- **Ticket:**` bullet).

---

## Step 1 — Resolve the plan output path

Determine where to write the master plan. Try these locations in order, picking the first that exists under the current git repository root (`git rev-parse --show-toplevel`):

1. `context/tickets/`
2. `docs/plans/`
3. `.claude/plans/master/`

If multiple exist, prefer the order above. If **none** exist, use the **binary-confirm pattern** (avoids `AskUserQuestion`'s 4-option cap):

1. **Print** the candidate directories as a plain-text numbered list with creation status:
   ```
   No standard plan directory found. Candidate locations under <git root>:
     1. context/tickets/ — does not exist (will create)
     2. docs/plans/ — does not exist (will create)
     3. .claude/plans/master/ — does not exist (will create)
   ```
2. **Call `AskUserQuestion`** with exactly two options:
   - **Option 1 (recommended):** `"Create context/tickets/ and use it"` — description: "Make the standard ticket-style directory and write the plan there."
   - **Option 2:** `"Cancel — I'll re-run with explicit path"` — description: "Stop now. Re-run /planning-tools:plan-master with the path arg set explicitly."

The plan filename defaults to:
- `<TICKET-ID>-PLAN.md` if the topic is a ticket ID
- A kebab-case slug derived from the topic otherwise

Once the directory is settled, confirm the **final plan file path** (directory + filename) with the user via `AskUserQuestion`: `"Use <path>"` / `"Choose different"` — exactly 2 options. Both fixed (FIXED-pattern, safe).

---

## Step 2 — Discovery pre-flight (skip if `--context` was supplied)

If `--context <report-path>` is supplied, **skip this step** and go to Step 3.

Otherwise, run the same four stages as `/planning-tools:plan-context`:

1. **Stage 1 — Triage** (no subagents): Read the source artifact, scan likely context locations, propose a domain partition.
2. **Stage 2 — Confirm domains** (binary `AskUserQuestion`): print the proposed N domains as a plain-text numbered list, then call `AskUserQuestion` with exactly two options — `"Proceed with all N domains"` / `"Cancel — I'll re-run with --domains"`. Never multi-select. Skip Stage 2 entirely if `--domains` was supplied or Triage yielded a single trivial domain. (Same pattern as `/planning-tools:plan-context` Stage 2.)
3. **Stage 3 — Parallel Explore**: dispatch `plan-context-worker` subagents in a single message, one per confirmed domain. Each returns its full findings as its final message and best-effort writes it to `/tmp/plan-context/<topic-slug>/<domain>.md`. **If Step 0 fetched a ticket source**, include the `{ title, body, comments[], url }` block verbatim in every worker prompt so each domain agent sees the same acceptance criteria + decision history.
4. **Stage 3.5 — Persist + backstop (orchestrator-owned)**: do **not** assume the worker wrote its file (Opus 4.8 workers frequently skip the `Write`). After all workers complete, confirm each expected `/tmp/plan-context/<topic-slug>/<domain>.md` exists and is non-empty (`Bash: test -s <path>` or a quick Read); for any missing or empty file, `Write` it from that worker's returned final message. Every findings file must exist on disk before Stage 4 and before the architect reads them in Step 3.
5. **Stage 4 — Verify**: read 3–6 critical files each worker cited to confirm patterns hold.

Capture the worker findings paths — you will pass them to the architect in Step 3.

---

## Step 3 — Synthesis (architect agent)

Dispatch the `plan-master-architect` agent (opus). The agent receives:

- The **topic**
- Paths to all worker findings (either from Step 2 or from the supplied `--context` directory)
- The **output file path** resolved in Step 1
- **Today's date**
- **Ticket context block** (optional) — if Step 0 fetched a ticket source, pass `{ title, body, comments[], url }` verbatim. The architect uses this for the Context block, the `- **Ticket:** <url>` bullet, and Open Questions extraction.

The architect reads the `master-plan-methodology` skill, then composes the master plan: universal core sections + trigger-based optional sections. It writes the plan to disk. Integer phases only. Open Questions at the top. No sizing.

When the architect completes, **do not re-read the plan in the main conversation** — the architect already returned a one-paragraph summary (path, phase count, optional sections included, propagated open questions). Surface that summary to the user.

---

## Step 4 — Hand-off

Tell the user:
- The plan path
- The number of phases
- The list of optional sections included
- Any Open Questions that propagated from the worker findings

Suggest next steps:
- `/planning-tools:plan-verify <path>` to audit the plan
- Open the plan and edit any Open Questions before iterating
- When ready, copy the first phase into Claude Code's built-in `/plan` to start execution

Then **stop**. The user drives the next move.

---

## Mandatory Use of AskUserQuestion

The main conversation owns all user interaction. Subagents never call `AskUserQuestion`.

- **Plan output path resolution** (Step 1) — confirm the chosen path or pick from candidates.
- **Domain confirmation** (Step 2 Stage 2) — same pattern as `/planning-tools:plan-context`.
- **If the topic cannot be located** — ask whether to proceed with a free-form scope.

The architect agent never asks the user anything. If it encounters ambiguity, it propagates the question into the plan's Open Questions section for the user to resolve manually.

## Notes

- The plugin is **project-agnostic**. The architect chooses optional sections based on what the worker findings indicate the work touches, not from ticket prefixes or any plan-type classifier.
- Plans are written to the user's project (git-versioned), not to `~/.claude/plans/` (which is reserved for per-session plan-mode files via `/planning-tools:plan-delete`).
- Reusing a `/planning-tools:plan-context` report via `--context` lets you separate exploration (fast, no commitment) from synthesis (committed, opus-backed). Recommended workflow for non-trivial topics.
