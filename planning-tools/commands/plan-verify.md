---
description: "Audit a drafted master plan against the plan-verification-checklist. Dispatches the plan-verifier agent, presents findings, optionally appends a Verified marker on user approval."
argument-hint: "<path to master plan>"
---

You are **auditing a master planning document** against the `plan-verification-checklist` skill. The audit emits Critical/Important/Suggestion findings with a PASS/FAIL verdict. On PASS, you may append a Verified marker to the plan's context block — a `- **Verified:** YYYY-MM-DD` bullet (v0.3.3+), or a `> **Verified:** YYYY-MM-DD` line on a legacy blockquote plan — but only with the user's explicit approval.

**Input:** `$ARGUMENTS` — the path to the master plan.

If arguments are empty, resolve the plan via the **binary-confirm pattern** (avoids `AskUserQuestion`'s 4-option cap, which would overflow on the common case of 8+ candidate plans across `context/tickets/`, `docs/plans/`, `.claude/plans/master/`):

1. **Glob** `context/tickets/*-PLAN.md`, `docs/plans/*.md`, `.claude/plans/master/*.md` (whichever exists) under the git root. Sort by modification time, newest first.
2. **0 candidates:** error with the three searched paths and a hint to pass an explicit path.
3. **1 candidate:** use it. Print the resolved path. Continue to Step 1.
4. **2+ candidates:** print the candidate list as plain text with the most-recently-modified at the top:
   ```
   N candidate master plans found (most-recent first):
     1. context/tickets/CI-21-PLAN.md — modified <date>
     2. context/tickets/CI-08-LITE-PLAN.md — modified <date>
     ...
     N. docs/plans/foo.md — modified <date>
   ```
   Then call `AskUserQuestion` with exactly two options:
   - **Option 1 (recommended):** `"Verify the most-recently-modified plan (#1)"` — description: "Audit \<path of #1\>."
   - **Option 2:** `"Cancel — I'll re-run with explicit path"` — description: "Stop. Re-run /planning-tools:plan-verify <path> to target a specific plan."

   Branch on the answer. On Proceed, use the #1 (most-recently-modified) plan and continue to Step 1. On Cancel, stop.

---

## Step 1 — Dispatch the verifier agent

Dispatch the `plan-verifier` agent (sonnet). The agent receives:

- The **plan path** to audit
- An **output file path** for the verification report (e.g., `/tmp/plan-verify/<plan-basename>-verification.md`)
- **Today's date**

The agent reads the `plan-verification-checklist` skill, audits the plan against every dimension, and writes a structured report. It returns a one-paragraph summary: total findings by severity, the verdict (`PASS` or `FAIL`), top 3 highest-impact fixes, and the report path.

**Do not re-read the full plan in the main conversation.** The agent does that.

---

## Step 2 — Present findings

Read the verification report file and surface the structured content to the user:

- **Severity counts:** Critical / Important / Suggestion
- **Top 3 highest-impact fixes** (from the agent's summary)
- **Verdict:** PASS or FAIL
- The full report path (the user can open it for the verbatim findings)

For each Critical finding, show the location and a one-line description. Do not dump the entire verbatim report in the conversation — the user has the file.

---

## Step 3 — Verified marker (only on PASS)

If the verdict is `PASS` (zero Critical, ≤ 2 Important), call `AskUserQuestion`:

- **Append the Verified marker** — adds the Verified marker to the plan's context block: a `- **Verified:** <today>` bullet (v0.3.3+ bulleted context block), or a `> **Verified:** <today>` line (legacy blockquote context block).
- **Skip the marker** — leave the plan as-is.

On `Append the Verified marker`:

1. Read the plan file.
2. **Detect the context-block shape:**
   - **Bulleted (v0.3.3+):** the metadata under the title is a `- **Label:** …` bullet list. Locate the **last consecutive `- ` context bullet** (e.g., the `- **Constraints:** …` bullet), before the `---` separator / `## Open Questions`. Insert `- **Verified:** YYYY-MM-DD` immediately after it.
   - **Legacy blockquote:** the metadata is a `>` blockquote. Locate the **last consecutive `>` line** before the `---` separator and insert `> **Verified:** YYYY-MM-DD` immediately after it.
3. Use the Edit tool to insert the marker with today's date in the shape matching the detected block. Do not convert a legacy blockquote to bullets — match what the plan already uses.
4. Confirm to the user: `Appended Verified marker to <path>.`

On `Skip the marker`, just acknowledge.

If the verdict is `FAIL`, **do not offer the marker option** — the plan is not ready to be marked verified. Recommend addressing the Critical findings first and re-running `/planning-tools:plan-verify`.

---

## Step 4 — Next steps

Suggest concrete actions based on the verdict:

- **PASS:** plan is ready for execution. Suggest the user copies Phase 1 into Claude Code's built-in `/plan` to start iterating.
- **FAIL:** suggest the user opens the plan and addresses the Critical findings (the report has line numbers). When done, re-run `/planning-tools:plan-verify <path>` for a second pass.

Then **stop**. The user drives the next move.

---

## Mandatory Use of AskUserQuestion

The main conversation owns all user interaction.

- **Plan path resolution** (if arguments empty) — let the user pick from candidate glob results.
- **Verified marker decision** (Step 3) — only offered on PASS. `Append` vs `Skip` via `AskUserQuestion`.

The `plan-verifier` agent never calls `AskUserQuestion` — it only emits the report.

## Notes

- This command **never modifies the plan content** except to append the Verified marker (and only with explicit user approval).
- Re-run `/planning-tools:plan-verify` after every plan edit. The audit is idempotent; running it on a clean plan is a no-op.
- The verification report is written to `/tmp/plan-verify/` (scratch). It is not part of the master plan and is not git-versioned.
- The verifier's checklist is owned by the `plan-verification-checklist` skill. Updates to audit dimensions should land in that skill — not in this command or the agent.
