---
description: "Auto-tick provenly-achieved phases of a master plan based on the current branch. /planning-tools:plan-tick (no args) audits and ticks all ACHIEVED phases. /planning-tools:plan-tick <phase> manually ticks one phase. No prompts."
argument-hint: "[phase-number] [path-to-plan]"
---

You are **ticking master-plan phases**. Two modes:

- **Auto mode** (no `<phase>` arg) — detect the current branch, find the master plan matching it, audit each unticked phase against the working tree + branch diff, tick all phases the auditor verdicts `ACHIEVED`. Conservative — never ticks an `UNCERTAIN` or `NOT_ACHIEVED` phase.
- **Manual override** (`<phase>` arg supplied) — tick that one phase in the resolved plan without running the auditor.

**Both modes are non-interactive.** You **must not** call `AskUserQuestion` anywhere in this command. If something cannot be resolved deterministically, error with a clear message — never prompt.

**Input:** `$ARGUMENTS`

Parse arguments:
- First positional integer → **manual override mode**, target phase number.
- Second positional path (or first if first arg is a path) → explicit plan file.
- No args → **auto mode**.

---

## Step 1 — Detect git context

Run a single bash block that captures:

```bash
git rev-parse --is-inside-work-tree || { echo "ERROR: not in a git repo"; exit 1; }
ROOT="$(git rev-parse --show-toplevel)"
BRANCH="$(git branch --show-current)"
# Base branch: try origin/HEAD symbolic-ref, fallback to main, then master
BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
[ -z "$BASE" ] && git rev-parse --verify --quiet origin/main >/dev/null && BASE=main
[ -z "$BASE" ] && git rev-parse --verify --quiet origin/master >/dev/null && BASE=master
[ -z "$BASE" ] && BASE=main
MERGE_BASE="$(git merge-base HEAD "$BASE" 2>/dev/null || git merge-base HEAD "origin/$BASE" 2>/dev/null)"
echo "ROOT=$ROOT"
echo "BRANCH=$BRANCH"
echo "BASE=$BASE"
echo "MERGE_BASE=$MERGE_BASE"
```

If not in a git repo, error: `/planning-tools:plan-tick requires a git repository.`

---

## Step 2 — Resolve the plan path

If the user supplied an explicit path argument: validate the file exists; otherwise error with the path.

Else:

1. **Discover candidate plans.** Glob `*.md` under `$ROOT/context/tickets/`, `$ROOT/docs/plans/`, `$ROOT/.claude/plans/master/`. Filter to files containing `## Implementation Phases`.
2. **0 candidates:** error with the searched paths.
3. **1 candidate:** use it.
4. **2+ candidates — branch-match selection:**
   - Normalize the branch name: strip leading `feature/`, `fix/`, `chore/`, `bugfix/`, `hotfix/`; lowercase; replace `_` and `/` with `-`.
   - For each candidate plan, normalize its basename: strip `-PLAN.md` or `.md`; lowercase; replace `_` and `/` with `-`.
   - Find candidates whose normalized basename appears as a substring of the normalized branch name (case + separator insensitive).
   - **1 match:** use it. Print: `Auto-ticking against <path> (branch <BRANCH> matched)`.
   - **2+ matches:** pick the **most-recently-modified** among the matches. Print: `Auto-ticking against <path> (branch <BRANCH> matched ambiguously; picked most-recent)`.
   - **0 matches:** fall back to the **most-recently-modified** plan across all candidates. Print: `Auto-ticking against <path> (no branch match; picked most-recent)`.

Never call `AskUserQuestion`. If multiple plans tie on modification time and no branch match exists, pick the one whose path sorts first alphabetically.

---

## Step 3 — Read and validate the plan

1. Read the plan file.
2. Find the `## Implementation Phases` heading. **Reject** `## Implementation Sub-Phases` or any other variant with an error pointing at the integer-only phase rule in `planning-tools:master-plan-methodology`.
3. Find the markdown table immediately after that heading.
4. Parse the table header. **Reject** if there is no `Status` column with this exact header text, and error:
   ```
   Plan does not conform to master-plan-methodology v0.2.1+ — the Implementation Phases table must include a Status column with emoji values (⏳ 🚧 ✅ ❌). See planning-tools:master-plan-methodology.
   ```
5. Parse the table rows. For each row, extract the Phase column value (trimmed) and the Status emoji.
6. If any phase value is non-integer (`1a`, `A`, `0.5`, ranges), error with the integer-only rule pointer — do not attempt to tick a malformed plan.

---

## Step 4a — Manual override mode (a `<phase>` argument was provided)

1. Look up the requested phase number in the parsed rows. If not found, error with the list of phase numbers actually present.
2. If the row's Status is already `✅`, report `Phase N already done in <path>. No changes.` and **stop** (idempotent).
3. Use the Edit tool with the entire row line as `old_string` and the modified line (only the Status emoji replaced with `✅`) as `new_string`.
4. Report: `Marked Phase N done in <path>. <K> phase(s) remain.`

**Stop here.** Do not run the auditor in manual mode.

---

## Step 4b — Auto mode (no `<phase>` argument)

1. Collect the list of **unticked phase numbers** — every row whose Status is not `✅` (`⏳`, `🚧`, `❌`, or empty).
2. If the list is empty, report: `All phases already done in <path>. Nothing to tick.` Stop.
3. **Dispatch the `plan-tick-auditor` agent** (sonnet). Pass:
   - The plan path
   - The base branch (`$BASE`)
   - The merge-base SHA (`$MERGE_BASE`)
   - The list of unticked phase numbers
4. Receive the auditor's structured report (Per-phase verdicts + Summary table).
5. **Surface the audit** to the user verbatim from the agent's report — copy the Per-phase verdicts and the Summary table into the conversation. The user sees exactly what was decided and why.
6. For each phase in the `ACHIEVED phases (safe to tick)` list, use the Edit tool to flip its Status emoji to `✅`. Use the full row line as `old_string` to anchor.
7. Skip rows the auditor verdicted `UNCERTAIN` or `NOT_ACHIEVED` — leave them as-is.

---

## Step 5 — Report

Output one final summary line:

```
Ticked <K> phase(s) in <path>: <list>.
<remaining-pending> phase(s) remain (<uncertain-count> UNCERTAIN, <not-achieved-count> NOT_ACHIEVED).
```

If `K == 0`:

```
No phases ticked. <remaining-pending> phase(s) remain — auditor verdicted them UNCERTAIN or NOT_ACHIEVED. To override, run /planning-tools:plan-tick <phase>.
```

If all phases are now `✅`, append: `All phases complete. Consider running /planning-tools:plan-verify to confirm and then opening the single PR per the Release section.`

---

## Strict no-prompt rule

This command **must not** call `AskUserQuestion` in any code path. The user explicitly chose auto mode for this command. If something is undecidable from local state:

- Use the deterministic fallback rule documented in each step.
- If no fallback exists, **error** with a clear message and a hint at the manual override or explicit path arg.

The `plan-tick-auditor` agent also must not call `AskUserQuestion` (and cannot, per its prompt). All decisions are made from local code state.

## Notes

- This command **only** writes Status cells. It does not commit, push, PR, modify Name cells (no strikethrough), or touch any other section.
- The command is **idempotent**: ticking an already-done phase is a no-op.
- The command only works on plans conforming to `planning-tools:master-plan-methodology` v0.2.1+ (integer phases, Status column with emoji values). Legacy plans require manual editing.
- The auditor is **conservative**. If it under-ticks (verdicts `UNCERTAIN` for a phase you know is done), run `/planning-tools:plan-tick <phase>` to override.
