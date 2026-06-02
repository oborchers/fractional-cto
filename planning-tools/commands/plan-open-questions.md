---
description: "Walk through a master plan's Open Questions one by one. For each question, read cited evidence, compose a context block with 2–4 alternatives (always including a Defer path), and capture the user's choice via a dedicated AskUserQuestion call per question (exactly one question per call — never batched). Apply all resolutions to the plan in one batch — moving answered questions from Open to Resolved. Runs entirely in the main conversation; no subagent dispatch."
argument-hint: "[path] [question-number]"
---

You are **walking the user through a master plan's Open Questions**. For each question you (a) ground the analysis by reading the question's cited evidence, (b) compose a context block in the canonical shape, (c) make **one** `AskUserQuestion` call carrying **exactly that one question** with 2–4 alternatives, and (d) accumulate the user's choice. Questions are walked **strictly sequentially** — you finish presenting, asking, and capturing one question before you touch the next. After all questions are walked you present a batch summary and apply all resolutions to the plan in one mutation.

**Never batch.** `AskUserQuestion` accepts up to 4 questions in a single call, but you must never use that to ask several open questions at once. One open question = one `AskUserQuestion` call. The user resolves each question in isolation.

**This command runs entirely in the main conversation.** Do not dispatch a subagent. All per-question reading, analysis, and alternative-generation happens here.

**Input:** `$ARGUMENTS`

Parse arguments:
- First positional path → explicit plan file (overrides branch-match).
- First or second positional integer → single-question targeting (walks only that Q-number).
- No args → auto-resolve plan from branch, walk all open questions.

---

## Step 1 — Detect git context

Lift verbatim from `/planning-tools:plan-tick` Step 1:

```bash
git rev-parse --is-inside-work-tree || { echo "ERROR: not in a git repo"; exit 1; }
ROOT="$(git rev-parse --show-toplevel)"
BRANCH="$(git branch --show-current)"
[ -z "$BRANCH" ] && { echo "ERROR: detached HEAD — /planning-tools:plan-open-questions requires a named branch"; exit 1; }
BASE="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
[ -z "$BASE" ] && git rev-parse --verify --quiet origin/main >/dev/null && BASE=main
[ -z "$BASE" ] && git rev-parse --verify --quiet origin/master >/dev/null && BASE=master
[ -z "$BASE" ] && BASE=main
echo "ROOT=$ROOT"
echo "BRANCH=$BRANCH"
echo "BASE=$BASE"
```

---

## Step 2 — Resolve the plan path

If the user supplied an explicit path argument, validate it exists; otherwise lift the branch-match + recency fallback from `/planning-tools:plan-tick` Step 2:

1. Glob `*.md` under `$ROOT/context/tickets/`, `$ROOT/docs/plans/`, `$ROOT/.claude/plans/master/`. Filter to files containing `## Implementation Phases`.
2. **1 candidate:** use it.
3. **2+ candidates — branch-match:** normalize branch + plan basenames the same way as `/plan-tick`; pick the substring match; on ties, most-recently-modified.
4. **0 candidates:** error with the searched paths and the manual override hint (`/planning-tools:plan-open-questions <explicit-path>`).

---

## Step 3 — Read and parse the Open Questions section

Read the plan file. Locate the `## Open Questions` heading.

**Detect the plan shape** by inspecting the content immediately after `## Open Questions`:

- **v0.3.0 list shape (preferred):** one or more `- **Q<N> — <question text>:** <prose>` bulleted lines appear. Use the bullet parser:
  - Each `- **Q<N> — ...:**` line starts one question. Capture `<N>` (integer), `<question text>` (the text between the em-dash and the colon), and the inline prose after the colon plus any continuation prose on indented sub-lines until the next `- **Q` bullet or the next `## ` heading.
  - Record each question as `{ n, questionText, contextProse, originalBullet }`.

- **v0.2.x table shape (legacy):** a markdown table with `| Q | Blocking? |` header appears. Use the table parser:
  - Each row's first cell (Q column) carries the question — typically formatted `Q<N> — <question text>`. Parse out `<N>` and `<question text>`. Capture the row's other cells as `contextProse`.
  - Emit a one-line note: `Plan uses v0.2.x table shape for Open Questions — supported during transition window. Consider migrating to v0.3.0 list shape (see planning-tools:master-plan-methodology).`

- **Neither:** error with `Could not locate Open Questions in <plan-path>. Expected a v0.3.0 bulleted list (- **Q<N> — ...:**) or a v0.2.x | Q | Blocking? | table under ## Open Questions.`

If the section exists but contains only an empty-state placeholder like `_(All N resolved YYYY-MM-DD — see Resolved Questions table below.)_` or no questions at all, treat as **zero open questions**.

---

## Step 4 — Handle the empty case

If zero open questions were parsed, report `No open questions in <plan-path>. Nothing to do.` and **stop**.

---

## Step 5 — Optional single-question targeting

If a `<question-number>` argument was supplied:

- Filter the parsed questions to that one Q-number.
- If the requested number doesn't exist in the parsed list, error with the list of Q-numbers actually present: `Plan has no Q<N>. Open questions: Q1, Q3, Q5, Q7. Re-run with one of those.`

Otherwise walk all parsed questions.

---

## Step 6 — Per-question walkthrough (main conversation)

For each open question to address, do all of the following **in the main conversation**. Do not dispatch any agent.

**Walk strictly one question at a time.** Fully present, ask, and capture question *i* before reading any evidence for question *i+1*. Never prepare a single `AskUserQuestion` call that covers several questions — even if the questions look related or trivial. Each open question is its own round-trip so the user can consider it in isolation.

### (a) Read evidence anchors

Scan the question text + `contextProse` + the surrounding plan body for concrete anchors:

- File paths (`src/foo/bar.ts`, `supabase/functions/x/index.ts`, etc.) with or without line ranges (`path:line` or `path:line-line`).
- ADR references (`ADR-NN`, `context/adrs/NN-<slug>.md`).
- Ticket IDs (`AIA-1234`, `CI-21`).
- Named symbols (functions, types, SQL identifiers) you can grep for in the codebase.

Read the most question-adjacent anchors with the Read tool — **cap at ~5 reads per question** to keep context bounded. If more than 5 anchors are cited, pick the ones the question's prose most directly mentions (skip anchors that are only in the plan's prelude / context block unless the question's analysis hinges on them).

If a ticket ID is present and the question seems to need ticket comment context, also fetch via the relevant source adapter (`mcp__linear-server__get_issue` + `list_comments`, or `gh issue view --comments`) — but only when the question text suggests ticket-thread context matters; don't fetch by default.

### (b) Compose the context block

Print the block to the user in the conversation, following this canonical shape:

```markdown
## Q<N>: <full question text>

<1–2 context paragraphs explaining what's at stake. Ground every claim in the reads from step (a) — cite path:line, ADRs, etc. Write so the reader can decide without re-reading the plan.>

**Why X**

<When the question has analytical depth, add this sub-section explaining one side of the tradeoff.>

**Why it could still matter**

<Counterargument or alternative framing.>

**Risk profile**

<What's the downside of getting this wrong? What's the cost of deferring?>

## Alternatives

### Option 1: <short title> (Recommended, if applicable)

<One paragraph: what this means concretely, what changes in the plan if chosen, who benefits.>

### Option 2: <short title>

<One paragraph.>

### Option 3: <short title>

<One paragraph.>

### Option 4 (always): Defer — keep open

<One paragraph: leave this question in Open Questions for now; the user will resolve manually or in a later /plan-open-questions run.>
```

Adapt the shape to the question's nature:

- For mechanical questions ("which directory should X live in?"), skip the "Why X / Why it could matter / Risk profile" sub-analysis — just 1 context paragraph and the alternatives.
- For deep analytical questions (like the SA-1606 picklist locale question), include the full sub-analysis.
- **Cite `path:line` for every concrete claim** about code. Vague claims are unhelpful.
- Mark exactly **one** alternative as **Recommended** when an obvious best answer exists. Skip the Recommended label when the choice is a genuine tradeoff.

### (c) Hard cap at 4 alternatives

`AskUserQuestion` accepts at most 4 options. If the natural answer set exceeds 4:

- Consolidate similar alternatives (e.g., "swap to SystemModstamp + retry once" and "swap to SystemModstamp + retry three times" become "swap to SystemModstamp with retry").
- Move lower-confidence alternatives into the "Defer" path's prose ("Defer; alternatives considered but not yet chosen: foo, bar"). The user can then pick those via the harness's free-text "Other" path.

### (d) Always include a "Defer — keep open" alternative

One of the 2–4 options is always the Defer path. When the natural answer set has 3 options, Defer is the 4th. When it has 2 options, Defer is the 3rd. When it has only 1 obvious answer, present that as Option 1 and Defer as Option 2.

### (e) Call `AskUserQuestion`

**This call contains exactly one question — a single entry in the `questions` array.** One `AskUserQuestion` call per open question; never place two or more open questions in the same call, even though the tool accepts up to 4 questions per call. Make the call only after *this* question's context block has been printed, and before you read the next question's evidence. The walk is one round-trip per question, always.

Pass the 2–4 alternatives as options:

- `label` = the alternative's short title (e.g., `"Leave on CreatedDate"`, `"Defer — keep open"`)
- `description` = one sentence summarizing the tradeoff
- `multiSelect: false` always — each question gets exactly one chosen answer.

If one alternative is the Recommended one, place it first and include `(Recommended)` in its label.

### (f) Capture the choice

Record the user's selection in an in-memory list of resolution objects:

```
{
  questionId: "Q<N>",
  questionText: "<full question text>",
  originalBullet: "<original line in Open Questions section>",
  chosenLabel: "<label of the option the user picked>",
  chosenDescription: "<description of the option>",
  freeTextOther: "<text the user typed, if they picked the 'Other' free-text path; else empty>",
  deferred: <true if the chosen label is "Defer — keep open"; else false>
}
```

For "Defer", mark `deferred: true` — these questions will stay in `## Open Questions` after apply.

Loop to the next question. Do not mutate the plan yet.

---

## Step 7 — Apply gate

When all questions are walked, present the accumulated resolutions as a plain-text summary in the conversation:

```
Resolutions for <plan-path>:
  Q1 → Leave on CreatedDate (minimum blast radius)
  Q2 → Also swap to SystemModstamp
  Q3 → Defer — keep open
  Q4 → Option C: per-EF catch in get-finance-data
```

Then call `AskUserQuestion` with these three options:

- **Option 1 (recommended):** `"Apply all <K> resolutions to <plan-path>"` — description: "Move answered questions from Open Questions to Resolved Questions. K = answered count; deferred questions stay in Open."
- **Option 2:** `"Show diff first"` — description: "Print a unified diff of the Open Questions and Resolved Questions sections before applying."
- **Option 3:** `"Discard"` — description: "Throw away all resolutions. Plan is untouched."

### Show-diff-first sub-flow

If the user picks "Show diff first":

1. Compute the proposed before/after for both sections.
2. Print a unified diff via `diff -u` (use Bash with two temp files) or hand-roll a brief diff if `diff` is unavailable.
3. Re-prompt with binary `AskUserQuestion`: `"Apply <K> resolutions"` / `"Discard"`.

### Discard

Stop without writing.

---

## Step 8 — Apply (mutate the plan)

For each non-deferred resolution:

### Remove from `## Open Questions`

- **v0.3.0 list shape:** use Edit with the question's `originalBullet` (the full `- **Q<N> — ...:**` line including all inline prose after the colon) as `old_string`. If the original bullet has indented continuation prose on sub-lines, include those lines in `old_string` too so the entire question block is removed atomically.
- **v0.2.x table shape:** use Edit with the question's table row as `old_string`. Replace with empty string (remove the row entirely).

### Append to `## Resolved Questions`

Find the `## Resolved Questions` heading. If the heading does not exist in the plan (it should per the methodology, but defensively check), abort with an error.

- **v0.3.0 list shape:** append a new bullet at the **end** of the Resolved Questions section (immediately before the next `## ` heading or EOF):
  ```
  - **Q<N> — <question text>:** <chosenLabel>. <chosenDescription>. <freeTextOther if present>
  ```
- **v0.2.x table shape:** append a new row to the Resolved Questions table with the question text in the first cell and the resolution prose in the second cell.

Preserve all other plan content byte-for-byte. Do not normalize whitespace, do not reformat list markers, do not touch any section other than Open Questions and Resolved Questions.

---

## Step 9 — Report

Output one final summary:

```
Resolved <K> open question(s) in <plan-path>. <M> remain.
```

If any deferred questions remain, append: `Deferred: Q<N>, Q<M>.`

If zero questions were answered (all deferred), report: `No questions resolved (all deferred). Plan unchanged.`

---

## Mandatory Use of AskUserQuestion

Three `AskUserQuestion` call points, all in the main conversation:

- **Step 6 per-question** — **one call per question, exactly one question per call**, walked sequentially. 2–4 single-select options per question, always including a Defer path. Never bundle multiple open questions into one call, even though the tool accepts up to 4 questions per call.
- **Step 7 apply gate** — 3 options (`Apply / Show diff first / Discard`).
- **Show-diff-first sub-flow** — binary follow-up (`Apply / Discard`).

Two orthogonal caps apply: `[[askuserquestion-4option-cap]]` — never exceed 4 **options** per question; and (Step 6) exactly one **question** per call for this sequential walkthrough.

## Strict no-modify rules

- This command **only** writes to the `## Open Questions` and `## Resolved Questions` sections of the resolved plan. Every other section is preserved byte-for-byte.
- It never modifies any other file (no `gh`, no Linear MCP, no commits, no `.gitignore`).
- It is **idempotent on no-op**: re-running on a fully-resolved plan exits cleanly with "No open questions".

## No subagent dispatch

This command does not call any agent. All file reads, evidence gathering, context-block composition, and alternative-generation happen in the main conversation. See `[[no-subagents-for-procedural-wrappers]]`.

## Notes

- For the canonical Open Questions / Resolved Questions shape, see `planning-tools:master-plan-methodology` v0.3.0+.
- For branch + plan matching mechanics, this command lifts directly from `/planning-tools:plan-tick`.
- For the apply-gate UX, this command mirrors `/planning-tools:plan-progress`'s three-option gate.
