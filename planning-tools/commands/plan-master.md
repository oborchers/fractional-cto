---
description: "Draft a multi-phase master planning document. Runs Triage + Confirm + Parallel Explore + Verify (or reuses a /plan-context report), then dispatches plan-master-architect to synthesize. Writes to a project-local path."
argument-hint: "<topic> [--context <report-path>] [--domains a,b,c]"
---

You are **drafting a master planning document**. The output is a project-local `.md` file in the user's repository, written by the `plan-master-architect` agent following the `master-plan-methodology` skill.

**Input:** `$ARGUMENTS`

Parse the arguments:
- **Topic** (required) — a ticket ID, file path, or free-form scope statement.
- `--context <path>` (optional) — path to a scratch directory from a prior `/plan-context` run (containing per-domain worker findings). If supplied, **skip the discovery pre-flight** and go straight to synthesis.
- `--domains a,b,c` (optional) — pre-seed the domain partition (skips Stage 2 Confirm).

If arguments are empty, ask the user for a topic via `AskUserQuestion` before proceeding.

---

## Step 1 — Resolve the plan output path

Determine where to write the master plan. Try these locations in order, picking the first that exists under the current git repository root (`git rev-parse --show-toplevel`):

1. `context/tickets/`
2. `docs/plans/`
3. `.claude/plans/master/`

If multiple exist, prefer the order above. If **none** exist, ask the user via `AskUserQuestion`:

- The three candidates above (with "create new" alongside each)
- An "Other" path the user types

The plan filename defaults to:
- `<TICKET-ID>-PLAN.md` if the topic is a ticket ID
- A kebab-case slug derived from the topic otherwise

Confirm the resolved path with the user via `AskUserQuestion` (`Use <path>` vs `Choose different`) before any work.

---

## Step 2 — Discovery pre-flight (skip if `--context` was supplied)

If `--context <report-path>` is supplied, **skip this step** and go to Step 3.

Otherwise, run the same four stages as `/plan-context`:

1. **Stage 1 — Triage** (no subagents): Read the source artifact, scan likely context locations, propose a domain partition.
2. **Stage 2 — Confirm domains** (`AskUserQuestion`): present the proposed partition; user can add/remove/edit. Skip if `--domains` was supplied or Triage yielded a single trivial domain.
3. **Stage 3 — Parallel Explore**: dispatch `plan-context-worker` subagents in a single message, one per confirmed domain. Each writes findings to `/tmp/plan-context/<topic-slug>/<domain>.md`.
4. **Stage 4 — Verify**: read 3–6 critical files each worker cited to confirm patterns hold.

Capture the worker findings paths — you will pass them to the architect in Step 3.

---

## Step 3 — Synthesis (architect agent)

Dispatch the `plan-master-architect` agent (opus). The agent receives:

- The **topic**
- Paths to all worker findings (either from Step 2 or from the supplied `--context` directory)
- The **output file path** resolved in Step 1
- **Today's date**

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
- `/plan-verify <path>` to audit the plan
- Open the plan and edit any Open Questions before iterating
- When ready, copy the first phase into Claude Code's built-in `/plan` to start execution

Then **stop**. The user drives the next move.

---

## Mandatory Use of AskUserQuestion

The main conversation owns all user interaction. Subagents never call `AskUserQuestion`.

- **Plan output path resolution** (Step 1) — confirm the chosen path or pick from candidates.
- **Domain confirmation** (Step 2 Stage 2) — same pattern as `/plan-context`.
- **If the topic cannot be located** — ask whether to proceed with a free-form scope.

The architect agent never asks the user anything. If it encounters ambiguity, it propagates the question into the plan's Open Questions section for the user to resolve manually.

## Notes

- The plugin is **project-agnostic**. The architect chooses optional sections based on what the worker findings indicate the work touches, not from ticket prefixes or any plan-type classifier.
- Plans are written to the user's project (git-versioned), not to `~/.claude/plans/` (which is reserved for per-session plan-mode files via `/plan-delete`).
- Reusing a `/plan-context` report via `--context` lets you separate exploration (fast, no commitment) from synthesis (committed, opus-backed). Recommended workflow for non-trivial topics.
