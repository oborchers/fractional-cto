---
description: "Pre-load context for a master plan — Triage proposes domains, user confirms, parallel Explore agents investigate, direct Reads verify findings. Emits a scope report. No plan file written."
argument-hint: "[topic | path] [--domains a,b,c]"
---

You are **pre-loading context** for a future master plan. The user will run `/planning-tools:plan-master` later (with the `--context <this-report>` flag, optionally) to draft the actual plan. **You are NOT writing a plan file, NOT entering plan mode, NOT calling `ExitPlanMode`.** You run four stages and emit a structured scope report — then stop.

**Input:** `$ARGUMENTS`

Parse the arguments:
- A file path → Read it first; it is the planning source artifact.
- A topic name / ticket ID → treat it as a scope statement; locate the source artifact via Glob if obvious (e.g., `context/tickets/<ID>-*.md`).
- `--domains a,b,c` flag (anywhere in arguments) → pre-seed the Stage 2 proposal with this list.
- Empty arguments → ask the user for a topic or path before starting Stage 1.

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

## Stage 2 — Confirm domains (`AskUserQuestion`)

Present the proposed partition to the user via `AskUserQuestion` (multi-select):

- Each proposed domain becomes one option labelled with the domain name and a short scope hint.
- Allow the user to deselect domains they don't want investigated.
- The "Other" path lets the user add a domain (free-text).

**Skip Stage 2 entirely if:**
- `--domains a,b,c` was supplied — use that list verbatim.
- Triage proposed only one domain — fan out to a single Explore agent with no Confirm step.

After confirmation, the surviving list of domains drives Stage 3.

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

Agent count = number of confirmed domains.

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

- `/tmp/plan-context/<topic-slug>/<domain1>.md`
- `/tmp/plan-context/<topic-slug>/<domain2>.md`
- ...
```

After emitting the report, **stop**. The user will either run `/planning-tools:plan-master --context <intermediate-dir>` to draft the plan, or iterate by re-running `/planning-tools:plan-context` with adjusted domains.

---

## Mandatory Use of AskUserQuestion

- **Stage 2 (Confirm domains)** — the main conversation calls `AskUserQuestion` (multi-select) after Triage proposes domains. Subagents never call it.
- If the source artifact cannot be located (Read fails on a supplied path, or the topic doesn't resolve to a file), ask the user via `AskUserQuestion` whether to proceed with the topic as a free-form brief or to provide a path.

The main conversation owns all user interaction. Subagents only fetch and report.

## Notes

- This command is a **port and generalization** of `aia-knowledge-platform-interface/.claude/commands/verify-plan.md` with an added explicit Triage + Confirm stage and project-agnostic domain selection.
- It writes intermediate worker findings to `/tmp/plan-context/<topic-slug>/`. These are scratch files, not the master plan — they are inputs to `/planning-tools:plan-master`.
- It does **not** modify the project, the plan file, or anything in `~/.claude/plans/`.
