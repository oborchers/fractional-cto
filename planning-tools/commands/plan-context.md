---
description: "Pre-load context for a master plan — Triage proposes domains, user confirms, parallel Explore agents investigate, direct Reads verify findings. Emits a scope report. No plan file written."
argument-hint: "[topic | path] [--domains a,b,c]"
---

You are **pre-loading context** for a future master plan. The user will run `/planning-tools:plan-master` later (with the `--context <this-report>` flag, optionally) to draft the actual plan. **You are NOT writing a plan file, NOT entering plan mode, NOT calling `ExitPlanMode`.** You run four stages and emit a structured scope report — then stop.

**Input:** `$ARGUMENTS`

Parse the arguments:
- A file path → Read it first; it is the planning source artifact.
- A ticket ID or ticket URL → treat it as a scope statement; **also** run the Stage 0 ticket-source detection below to fetch ticket content via adapter.
- A topic name → treat it as a scope statement; locate the source artifact via Glob if obvious (e.g., `context/tickets/<ID>-*.md`).
- `--domains a,b,c` flag (anywhere in arguments) → pre-seed the Stage 2 proposal with this list.
- Empty arguments → ask the user for a topic or path before starting Stage 1.

---

## Stage 0 — Ticket-source detection (optional)

Before Stage 1, run pattern detection against the first argument. If it matches one of these forms, **fetch the ticket source** via the adapter contract codified in `planning-tools:progress-methodology`:

| Pattern | Provider |
|---|---|
| `^[A-Z]{2,6}-\d+$` (e.g., `AIA-1234`, `CI-21`) | Linear |
| `^https://linear\.app/.+/issue/([A-Z]{2,6}-\d+)/` | Linear |
| `^https://github\.com/([^/]+)/([^/]+)/(issues\|pull)/(\d+)` | GitHub |
| `^([^/\s]+/[^/\s]+)#(\d+)$` (e.g., `org/repo#42`) | GitHub |

On a match:

1. **Fetch** title, body, and **all comments** (no cap — per the comment-fetch policy in `progress-methodology`):
   - Linear: `mcp__linear-server__get_issue(id)` + `mcp__linear-server__list_comments(issueId)`.
   - GitHub: `gh issue view <N> --repo <owner>/<repo> --json title,body,state,url,comments` (or `gh pr view`).
2. **Augment the Stage 1 Triage source artifact** with the fetched `{ title, body, comments[], url }` block. Triage scans comments for acceptance criteria, prior decisions, and unresolved questions to flag in the Open Questions section of the scope report.
3. **Persist the ticket block** so Stage 3 workers receive it verbatim (each domain agent sees the same acceptance criteria + decision history).

If the matched provider's MCP/CLI is unavailable, **fail loudly**: e.g., `Linear MCP not loaded — cannot fetch <ticket>. Re-run on a session that has the Linear MCP, or pass the topic as free-form text.` Do not silently degrade.

If no pattern matches → no fetch, proceed to Stage 1 with the original arguments unchanged.

---

## Stage 1 — Triage (no subagents)

Orient yourself before any agent fires. This is a cheap pass the main conversation runs:

1. **Read the source artifact** if it is a file. One Read call.
2. **Scan likely context locations** with a single shallow pass — list the contents of `context/`, `docs/`, the project root (looking for `PRD.md`, `ROADMAP.md`, `ARCHITECTURE.md`, `CLAUDE.md`), and any paths cited inside the source artifact.
3. **Propose a non-overlapping domain partition.** Each domain is one slice the parallel agents will own. Typical domains:
   - `backend` — server-side code, edge functions, APIs
   - `frontend` — UI components, screens, state
   - `analytics` — event shapes, tracking
   - `i18n` — locale files
   - `research` — `context/research/` docs cited by the topic
   - `adrs` — ADRs touched (`context/adrs/`)
   - `infra` — deployment, CI, observability
   - `tests` — test layout, fixtures, e2e
   - Add or remove based on what the source actually touches

Output the proposed partition as a numbered list with a one-line scope hint per domain.

---

## Stage 2 — Confirm domains (binary `AskUserQuestion`)

**Why binary, not multi-select:** `AskUserQuestion` has a hard maximum of 4 options per question. Real triages routinely propose 5–10 domains (backend, frontend, analytics, i18n, research, adrs, infra, tests). A multi-select with one option per domain overflows the cap and crashes the command. The binary fallback works for any N.

**The pattern:**

1. **Print** the proposed partition as a plain-text numbered list directly in the conversation (not via `AskUserQuestion`). One line per domain with a one-line scope hint:

   ```
   Proposed N domains:
     1. backend — Supabase edge functions in supabase/functions/<area>/
     2. frontend — React components under src/features/<area>/
     3. analytics — event shapes referenced in analytics/<area>.ts
     ...
     N. <domain> — <hint>
   ```

2. **Call `AskUserQuestion`** with exactly one question and exactly **two** options:

   - **Question:** `"Proceed with all N domains?"`
   - **Option 1 (recommended):** `"Proceed with all N domains"` — description: "Continue to Stage 3 and dispatch one plan-context-worker per domain."
   - **Option 2:** `"Cancel — I'll re-run with --domains"` — description: "Stop now. Re-run /planning-tools:plan-context with --domains a,b,c to specify exactly which domains to investigate."

3. **Branch on the answer:**
   - **Proceed:** continue to Stage 3 with the full proposed list.
   - **Cancel:** stop and instruct the user to re-run with `--domains <list>`.

**Skip Stage 2 entirely if:**
- `--domains a,b,c` was supplied — use that list verbatim (no print, no question).
- Triage proposed only one domain — fan out to a single Explore agent with no Confirm step.

This is the **canonical binary-confirm pattern** for the plugin. The same pattern applies to any dynamic-length list (candidate plans, candidate paths, etc.) — never use multi-select for dynamic data, because the 4-option cap will eventually break it.

---

## Stage 3 — Parallel Explore (one agent per confirmed domain)

Dispatch `plan-context-worker` subagents **in a single message** (parallel). Each agent receives:

- The **topic** (file path or scope statement)
- Its **domain assignment** (one of the confirmed domains)
- **Scope hints** — the files/paths Triage identified as in-scope for that domain
- An **output file path** for its intermediate findings document (in a per-session scratch directory, e.g., `/tmp/plan-context/<topic-slug>/<domain>.md`)

Each agent's prompt must be **self-contained** — it has not seen this conversation. Every prompt states:

- The topic and domain
- Files/paths to investigate
- The required deliverable: concrete `path:line` references, existing patterns, reusable helpers, constraints, suggested phase split for that domain
- The explicit constraint: **"Report only — do not write code. Do not propose changes."**
- **If Stage 0 fetched a ticket source:** include the `{ title, body, comments[], url }` block verbatim in every worker prompt so each domain agent has the same ticket context.

Agent count = number of confirmed domains.

### Stage 3.5 — Persist + backstop (orchestrator-owned)

Each worker returns its full findings document as its final message and best-effort writes it to its output path. **Do not assume the worker wrote the file** — Opus 4.8 workers frequently return the findings but skip the `Write`. The orchestrator guarantees persistence:

1. After **all** workers complete, for each expected `/tmp/plan-context/<topic-slug>/<domain>.md`, confirm it exists and is non-empty (`Bash: test -s <path>` or a quick Read).
2. For any file that is **missing or empty**, `Write` it from that worker's returned final message.
3. Track which domains had to be backstopped — surface them in the scope report's "Worker findings" list.
4. **Do not proceed to Stage 4 until every expected findings file exists on disk and is non-empty.**

---

## Stage 4 — Verify (direct Reads, no subagents)

After all workers complete, read 3–6 critical files each worker cited to confirm:

- File paths exist
- Line numbers resolve
- Patterns described are actually present
- Imports and dependencies are accurate

If you find discrepancies, note them as **Verification deltas** in the report. Do **not** silently correct the workers' findings.

---

## Output: scope report

Emit a terse report to the user (in the conversation, not a file). The user will use this to drive `/planning-tools:plan-master`.

```markdown
# Scope report: <topic>

> **Source:** <path or scope statement>
> **Date:** <today>
> **Domains investigated:** <list>

## Scope summary
<One-sentence statement of what the planning subject is.>

## Key locations

### <domain 1>
- `<path>:<line>` — <one-line purpose>
- `<path>:<line>` — <one-line purpose>

### <domain 2>
- ...

## Constraints discovered
- **Naming convention:** <observed>
- **Shared libraries to reuse:** <list with paths>
- **ADRs that constrain this work:** <list>
- **Test patterns:** <observed>

## Verification deltas
<Claims from worker findings that didn't hold up under direct Read. Empty if all verified.>

## Open questions blocking /planning-tools:plan-master
<Things the user must decide before drafting the plan. Empty if all clear.>

## Suggested phase split

A non-binding suggestion for how to phase the work in the master plan. The architect will refine.

1. <Phase candidate — what it covers, key files>
2. <Phase candidate>
3. ...

## Worker findings (intermediate docs)

Append `(backstopped)` to any domain whose file the orchestrator had to write from the worker's returned message (the worker skipped its own `Write`).

- `/tmp/plan-context/<topic-slug>/<domain1>.md`
- `/tmp/plan-context/<topic-slug>/<domain2>.md` (backstopped)
- ...
```

After emitting the report, **stop**. The user will either run `/planning-tools:plan-master --context <intermediate-dir>` to draft the plan, or iterate by re-running `/planning-tools:plan-context` with adjusted domains.

---

## Mandatory Use of AskUserQuestion

- **Stage 2 (Confirm domains)** — the main conversation prints the proposed domain list as plain text, then calls `AskUserQuestion` with **exactly two options** (`Proceed` / `Cancel`). Never multi-select — the 4-option cap would crash on common N≥5 triages. Subagents never call `AskUserQuestion` at all.
- If the source artifact cannot be located (Read fails on a supplied path, or the topic doesn't resolve to a file), ask the user via `AskUserQuestion` whether to proceed with the topic as a free-form brief or to provide a path.

The main conversation owns all user interaction. Subagents only fetch and report.

## Notes

- This command is a **port and generalization** of `aia-knowledge-platform-interface/.claude/commands/verify-plan.md` with an added explicit Triage + Confirm stage and project-agnostic domain selection.
- It writes intermediate worker findings to `/tmp/plan-context/<topic-slug>/`. These are scratch files, not the master plan — they are inputs to `/planning-tools:plan-master`. **Persistence is orchestrator-owned (Stage 3.5):** a worker may return its findings as its final message without writing the file itself, so the main conversation verifies each expected file on disk after workers complete and writes any that are missing or empty from the worker's returned message. Never trust the worker's `Write` to have happened.
- It does **not** modify the project, the plan file, or anything in `~/.claude/plans/`.
