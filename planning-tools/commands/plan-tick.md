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

## Step 3 — Read, detect shape, and parse the plan

1. Read the plan file.
2. Find the `## Implementation Phases` heading. **Reject** `## Implementation Sub-Phases` or any other variant with an error pointing at the integer-only phase rule in `planning-tools:master-plan-methodology`.
3. **Detect the plan shape** by scanning the content immediately after the `## Implementation Phases` heading:

   - **v0.3.0 list shape (preferred):** one or more `### Phase <N>: <name> <emoji>` H3 headings appear under `## Implementation Phases`. Use the **heading parser** (step 4 below).
   - **v0.2.x table shape (legacy, transition-supported):** a markdown table with header row `| Phase | Name | Status | Scope |` appears immediately after the heading. Use the **legacy table parser** (step 5 below). Emit one note to the user: `Plan uses v0.2.x table shape — supported during transition window. Consider migrating to v0.3.0 list shape (see planning-tools:master-plan-methodology).`
   - **Neither:** error with `Plan does not conform to master-plan-methodology v0.3.0+ — Implementation Phases must use ### Phase <N>: <name> <emoji> H3 headings with - [ ] checklists (or, transitionally, the v0.2.x | Phase | Name | Status | Scope | table shape). See planning-tools:master-plan-methodology.`

### Step 4 — Heading parser (v0.3.0 list shape)

For each `### Phase <N>: <name> <emoji>` heading under `## Implementation Phases`:

- Extract `<N>` (the integer phase number, e.g., `1`, `2`, `10`).
- Extract `<emoji>` (the last token on the line, separated from the phase name by exactly one space — one of `⏳ 🚧 ✅ ❌`).
- Capture the scope as the text between this heading and the **next `### Phase` heading or next `## ` heading** (the scope text is the bulleted `- [ ]` / `- [x]` checklist).
- If `<N>` is non-integer (`1a`, `A`, `0.5`, ranges), error with the integer-only rule pointer.
- If `<emoji>` is missing or not one of `⏳ 🚧 ✅ ❌`, error with `Phase <N> heading does not end with a status emoji (⏳ 🚧 ✅ ❌). See planning-tools:master-plan-methodology v0.3.0 Status conventions.`

### Step 5 — Legacy table parser (v0.2.x)

For each row of the `| Phase | Name | Status | Scope |` table:

- Extract the Phase column value (trimmed) and the Status emoji.
- Reject if there is no `Status` column with this exact header text.
- Reject if any phase value is non-integer.

---

## Step 6a — Manual override mode (a `<phase>` argument was provided)

1. Look up the requested phase number in the parsed phases. If not found, error with the list of phase numbers actually present.
2. If the phase's Status is already `✅`, report `Phase N already done in <path>. No changes.` and **stop** (idempotent).
3. Edit the phase to flip its emoji to `✅`:
   - **v0.3.0 heading shape:** Edit the full `### Phase <N>: <name> <old-emoji>` line; preserve everything before the last token; replace only the last-token emoji with `✅`. Anchor with the exact heading line.
   - **v0.2.x table shape:** Edit the full row line; replace only the Status cell emoji with `✅`.
4. Report: `Marked Phase N done in <path>. <K> phase(s) remain.`

**Stop here.** Do not run the auditor in manual mode.

---

## Step 6b — Auto mode (no `<phase>` argument)

The audit runs **entirely in the main conversation**. No subagent is dispatched. See `[[no-subagents-for-procedural-wrappers]]` for the design choice.

1. Collect the list of **unticked phase numbers** — every phase whose Status is not `✅` (`⏳`, `🚧`, `❌`, or missing).
2. If the list is empty, report: `All phases already done in <path>. Nothing to tick.` Stop.
3. **Read the branch diff once.** Run `git diff <MERGE_BASE>...HEAD --name-only` to get the set of files modified on this branch. Cache this list — you will check phase scopes against it for every phase. Do not call `git diff` again per phase.

   ```bash
   git diff "$MERGE_BASE"...HEAD --name-only
   ```

4. **For each unticked phase, audit it inline:**

   a. **Extract evidence anchors** from the phase's scope text (the bulleted region under the `### Phase <N>:` heading for v0.3.0, or the Scope cell for v0.2.x):
      - **File paths** mentioned (anything matching a path pattern like `src/foo/bar.ts`, `supabase/functions/<x>/index.ts`, `__tests__/x.test.ts`, etc.).
      - **Symbol names** mentioned (function names, class names, type names, SQL identifiers, i18n keys, analytics event names).
      - **Exit criteria** (extracted from the bolded `**Exit criteria:**` scope item in v0.3.0; from prose in the Scope cell in v0.2.x).

   b. **Check file existence.** For each in-scope file path, Read it (or check it exists). If a file is referenced as needing to be created and is missing → strong `NOT_ACHIEVED` signal.

   c. **Check branch diff membership.** For each in-scope file path, check whether it appears in the cached diff name-only list. At least one file must appear in the diff for `ACHIEVED`.

   d. **Check symbol presence.** For each named symbol, grep the relevant file(s) for the symbol. The symbol must be present in the current working tree.

   e. **Check checkbox state (v0.3.0 only).** Count `- [ ]` vs `- [x]` items in the phase's scope. If every checkbox is `- [x]`, treat as a **strong additional `ACHIEVED` signal** — but still require diff-membership + file-existence to verdict `ACHIEVED`. An all-checked phase with no diff hits is still `NOT_ACHIEVED` (checkboxes can be ticked optimistically; code is the source of truth).

   f. **Tally** per the conservative verdict criteria table below.

5. **Verdict criteria (conservative — err toward NOT ticking):**

   | Verdict | All of these must hold |
   |---|---|
   | `ACHIEVED` | (a) every file path in Scope exists, (b) ≥1 in-scope file appears in the branch diff vs merge-base, (c) every named symbol is present in the working tree, (d) no scope-mentioned file is conspicuously absent. For v0.3.0 plans: an all-`- [x]` scope strengthens the verdict but does not on its own grant `ACHIEVED` — code evidence still required. |
   | `UNCERTAIN` | Some evidence present (e.g., files exist) but not enough — diff doesn't include the files, or a key symbol is missing, or the phase is non-code (docs/planning) and the audit cannot judge from code state. |
   | `NOT_ACHIEVED` | Scope references files that don't exist, or zero in-scope files appear in the branch diff, or named symbols are missing across the board. |

   **The default verdict is `NOT_ACHIEVED` / `UNCERTAIN`.** Only graduate to `ACHIEVED` with concrete evidence. The user can always manually tick via `/planning-tools:plan-tick <phase>` if the audit is too conservative; recovering from a wrongly-ticked phase is harder.

   **Non-code phases** (Scope describes planning, documentation, or analysis work with no code paths cited and no symbols to check) are `UNCERTAIN` by default. The user manually ticks these via `/planning-tools:plan-tick <phase>`.

6. **Surface the audit report verbatim to the user.** Use this exact shape:

   ```markdown
   # Plan Tick Audit Report

   > Plan: <path>
   > Branch base: <BASE> (merge-base <short-sha>)
   > Phases evaluated: <N>

   ## Per-phase verdicts

   ### Phase <N>: <name>
   - **Verdict:** ACHIEVED | UNCERTAIN | NOT_ACHIEVED
   - **Evidence:**
     - <one-line check result, e.g., `src/features/sf-links.ts` exists ✓>
     - <`getRoaUrl` symbol present at `src/features/sf-links.ts:42` ✓>
     - <file appears in branch diff ✓>
     - <(v0.3.0) checkbox state: 5/5 ticked>
   - **Conclusion:** <one short sentence>

   ### Phase <N+1>: …
   …

   ## Summary

   | Phase | Verdict |
   |---|---|
   | 1 | ACHIEVED |
   | 2 | ACHIEVED |
   | 3 | UNCERTAIN |
   | 4 | NOT_ACHIEVED |

   **ACHIEVED phases (safe to tick):** 1, 2
   **UNCERTAIN phases (leave for now):** 3
   **NOT_ACHIEVED phases (skip):** 4
   ```

   Every verdict must include 2–4 one-line evidence rows. "Symbol present in file" without a line number is too vague — say `getRoaUrl` defined at `src/features/sf-links.ts:42`.

7. For each phase in the `ACHIEVED phases (safe to tick)` bucket, use the Edit tool to flip its emoji to `✅`:
   - **v0.3.0 heading shape:** Edit the `### Phase <N>: <name> <old-emoji>` line, replacing the last-token emoji with `✅`. Anchor with the full heading line.
   - **v0.2.x table shape:** Edit the full row line; replace only the Status cell emoji with `✅`.

8. Skip phases verdicted `UNCERTAIN` or `NOT_ACHIEVED` — leave them as-is.

---

## Step 7 — Report

Output one final summary line:

```
Ticked <K> phase(s) in <path>: <list>.
<remaining-pending> phase(s) remain (<uncertain-count> UNCERTAIN, <not-achieved-count> NOT_ACHIEVED).
```

If `K == 0`:

```
No phases ticked. <remaining-pending> phase(s) remain — audit verdicted them UNCERTAIN or NOT_ACHIEVED. To override, run /planning-tools:plan-tick <phase>.
```

If all phases are now `✅`, append: `All phases complete. Consider running /planning-tools:plan-verify to confirm and then opening the single PR per the Release section.`

---

## Strict no-prompt rule

This command **must not** call `AskUserQuestion` in any code path. The user explicitly chose auto mode for this command. If something is undecidable from local state:

- Use the deterministic fallback rule documented in each step.
- If no fallback exists, **error** with a clear message and a hint at the manual override or explicit path arg.

All decisions are made from local code state.

## Notes

- This command **only** writes the status emoji (heading suffix for v0.3.0, Status cell for v0.2.x). It does not commit, push, PR, modify phase names (no strikethrough), or touch any other section.
- The command is **idempotent**: ticking an already-done phase is a no-op.
- Supports both **v0.3.0 list shape** (`### Phase <N>: <name> <emoji>` headings with `- [ ]` checklists) and **v0.2.x legacy table shape** (`| Phase | Name | Status | Scope |`). Shape detection is automatic.
- The audit is **conservative**. If it under-ticks (verdicts `UNCERTAIN` for a phase you know is done), run `/planning-tools:plan-tick <phase>` to override.
- **No subagent is dispatched.** The audit runs entirely in the main conversation. See `[[no-subagents-for-procedural-wrappers]]` for why.
