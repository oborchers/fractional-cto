---
name: master-plan-methodology
description: This skill should be used when authoring, reviewing, or modifying a multi-phase master planning document via the planning-tools plugin (especially the /plan-master and /plan-verify commands). Codifies the universal core sections, trigger-based optional sections, integer-only phase numbering, Open Questions placement, one-PR-per-plan rule, status conventions, evidence attribution, callouts, and cross-reference formats for master plans. Project-agnostic — no ticket-prefix or plan-type taxonomy.
version: 0.2.1
---

# Master Plan Methodology

A **master plan** is a long, multi-phase planning document that decomposes a topic, ticket, or roadmap item into actionable phases. Each phase maps 1:1 to a Claude Code `/plan`-mode session. The master plan is the durable artifact; the per-phase plans in `~/.claude/plans/<slug>.md` are ephemeral.

This skill codifies the **format and conventions** every master plan must follow. The `plan-master-architect` agent writes plans to this spec; the `plan-verifier` agent audits plans against it.

## The 5-step workflow

The plugin orchestrates master plans through five steps:

1. **`/planning-tools:plan-context [topic | path] [--domains a,b,c]`** — Pre-load context. Stage 1 Triage proposes domains, Stage 2 Confirm checks them with the user, Stage 3 dispatches parallel Explore agents (one per confirmed domain), Stage 4 verifies findings with direct Reads. Emits a scope report. **NO plan file written.**
2. **`/planning-tools:plan-master [topic] [--context <report-path>]`** — Draft the master plan. Reuses a fresh `/planning-tools:plan-context` report if `--context` is passed; otherwise runs the same Triage + Confirm + Explore + Verify pre-flight internally. Then synthesizes the multi-phase plan via the `plan-master-architect` agent (opus). Writes to a project-local path.
3. **`/planning-tools:plan-verify <path>`** — Audit the drafted plan. Dispatches the `plan-verifier` agent against the `plan-verification-checklist` skill, presents Critical/Important/Suggestion findings, and (on user approval) appends a `> **Verified:** YYYY-MM-DD` callout to the context block.
4. **Manual phase iteration** — User copies the next unticked phase into Claude Code's built-in `/plan`. Plan mode produces the per-phase plan in `~/.claude/plans/<slug>.md`. User executes the phase and manually ticks the row in the master plan.
5. **`/planning-tools:plan-delete`** — Clears the per-session plan file. Loop back to step 4 for the next phase.

## Project-local plan storage

The plugin discovers project-local plan paths in this order, picking the first that exists under the current git repository:

1. `context/tickets/`
2. `docs/plans/`
3. `.claude/plans/master/`

If none exist and the user does not specify a path, the architect asks via `AskUserQuestion` (the three candidates plus "create new"). Plan filenames default to `<TICKET-ID>-PLAN.md` if a ticket ID is supplied; otherwise the architect derives a kebab-case slug from the topic.

## Universal core sections

Every master plan **must** include these sections in this order:

1. **Title** (H1) — name + one-line synopsis
2. **Quoted context block** — Ticket(s), PRD/Source, Evidence, Depends on, Constraints
3. **Open Questions** — table of blocking questions, **placed immediately after the context block** (not at the end)
4. **Resolved Questions** — table of resolved questions (may be empty)
5. **Implementation Phases** — table with Phase, Name, Status, Scope columns
6. **Design Principles** — numbered list of opinionated rules
7. **What's NOT in <TOPIC> (and why)** — explicit out-of-scope items with reasoning

## Trigger-based optional sections

The architect adds these **based on what the work touches**, derived from the worker findings — never from a project taxonomy or filename prefix. Each trigger is independent.

| Trigger | Sections to include |
|---|---|
| Work touches database / schema | **Data Model** or **Schema**, **Rollback Procedure** |
| Work touches UI | **Problem Statement**, **Visual Design — ASCII Mockups**, **UI States** / **Skeleton Screens**, **Component Architecture**, **Layout Audit @ \<viewport\>**, **i18n** (Key / EN / locale), **Manual QA Checklist** |
| Work has measurable user-facing impact | **Analytics** (event shapes) |
| Work touches architecture / cross-cutting concerns | **Requirements Coverage** (Requirement / Source / Priority / Owner), **Architecture**, **Analysis**, **Concurrency Model**, **Non-Functional Requirements**, **Cross-Ticket Dependencies**, **Feature/Module Folder Structure** |
| Work has operational or financial impact | **Cost Summary** (€/mo or $/mo with assumptions), **Risks + Mitigations** (formal risk register), **Phase-specific Prerequisites**, **Appendix** (discovery artifacts) |
| Work fixes a production issue | **Code Changes (file × phase)**, **Recovery for Affected Records** |
| Work must be validated after merge / deploy | **Verification (post-merge / post-deploy)**, **Deployment Steps** |
| Work accumulates decisions | **Design Decisions** table (#, Issue, Decision, Rationale) — typically when ≥5 decisions accumulate |
| Work has hidden gotchas | **Key Implementation Notes** |
| Work changes over time | **Revision Log** |
| Work has tests | **Tests** (Unit / Integration / E2E) |
| Work has prerequisites | **Prerequisites** (what must ship first) |
| Project has guideline docs (e.g., `FEATURE.md`) | **\<Project\>.md Compliance** — checklist against those guidelines |
| Plan ships as a single PR (almost always) | **Release** — the *one* PR description that ships after all phases land: title, body summary, manual QA, deployment notes. The **only** place where `git push` / `gh pr create` belong. Optional but recommended for non-trivial plans. |

## One PR per master plan (non-negotiable)

A master plan ships as **one pull request**, opened once after the final phase lands — not one PR per phase.

**Per-phase `git commit` and `git push` are explicitly allowed and encouraged** — they keep the working branch in sync, give reviewers a clean per-phase history, and survive machine failures. What is *not* allowed is opening, merging, or requesting review on a PR per phase.

Phase scope **may** include:

- File paths to modify
- Code patterns and structure
- Local verification (tests pass, type-check passes, behavior verified)
- Exit criteria / Definition of Done
- `git add` / `git commit` / `git push` instructions (per-phase commits to the working branch are fine)

Phase scope **must not** include:

- `gh pr create` instructions
- "Open PR" / "Merge PR" / "Request review" instructions
- "Reviewer can sign off after this phase" or any per-phase PR handoff
- Per-phase merges to `main` / `master` / `develop` or any shared branch

If the work requires staged releases (e.g., a feature-flag rollout split across PRs), that is the rare exception and **must** be modelled as separate master plans, not as per-phase PRs inside one plan.

A single optional **Release** section at the bottom of the master plan describes the one PR that ships after all phases complete (title, body summary, manual QA steps to run before merge). This is the only place where `gh pr create` belongs.

## Integer phase numbering (non-negotiable)

Phases are numbered with **positive integers only**: `1, 2, 3, 4, …`.

**Forbidden:**
- `0`, `0.5`, `1.5` (no decimals)
- `1A`, `1B`, `2A` (no letter suffixes)
- `Phase A`, `Phase B`, `Phase C` (no letter-only)
- `Phase 0–5` (no ranges)
- `Implementation Sub-Phases` (no sub-phasing)

When sub-phasing feels tempting, either (a) collapse into a single phase with structured `Scope`, or (b) split into two integer-numbered phases.

The word **"Phase"** is reserved for these integer-numbered work units inside the master plan document. Internal command stages, workflow steps, or other process descriptions use **"Stage"** or **"step"** instead.

## No sizing estimates

XS/S/M/L, T-shirt sizes, time estimates, and any "effort" column are **not used**. Phases describe scope, not effort.

## Status conventions

The Implementation Phases table includes a `Status` column with these emoji:

- `⏳` Pending
- `🚧` In Progress
- `✅` Done
- `❌` Blocked

Strikethrough (`~~Phase 1: …~~`) on completed phase rows is allowed but not required.

## Skeleton template

```markdown
# <Title>: <one-line synopsis>

> **Ticket(s):** <Linear/Jira refs or n/a>
> **PRD / Source:** <doc paths>
> **Evidence:** <transcript YYYY-MM-DD speaker quote | bug report | research path:line>
> **Depends on:** <ticket> (<specific artifact>)
> **Constraints:** <viewport, env, etc.>

---

## Open Questions
| Q | Blocking? |
|---|---|

## Resolved Questions
| Q | Resolution |
|---|---|

## Implementation Phases

| Phase | Name | Status | Scope |
|---|---|---|---|
| 1 | … | ⏳ | Concrete file paths, code snippets, exit criteria |
| 2 | … | ⏳ | … |

## Design Principles
1. …

## What's NOT in <TOPIC> (and why)
- …

<!-- Trigger-based optional sections inserted here based on what the worker findings indicate the work touches -->
```

## Evidence-attribution rules

Every factual claim in a master plan must be traceable to a source. Use these formats:

- **Transcript quotes:** `<Speaker> <env> bug <YYYY-MM-DD> (<ticket>, <case-ref>) — "<quote>"`
- **ADRs:** `ADR-NN` (short) or `context/adrs/NN-<slug>.md` (path)
- **Roadmap:** `Decisions locked <YYYY-MM-DD>` or `ROADMAP.md#<section>`
- **Code:** `<repo-relative-path>:<line>` (with line number)
- **Research docs:** `context/research/<file>.md` (path)

## Callout / admonition conventions

Bold-prefix lines for inline emphasis (do **not** use GitHub-style `> [!NOTE]` admonitions):

- `**Decision:** …` — a settled choice
- `**Rationale:** …` — the reasoning for a Decision
- `**Risk:** …` — a known risk
- `**Mitigation:** …` — how the Risk is addressed
- `**Note:** …` — informational aside

Blockquotes (`>`) are reserved for **invariants and constraints** (e.g., `> Templates are immutable after first publish`), and for the **top-of-file context block**.

## Cross-reference conventions

- **Tickets:** `[CI-15](../CI-15-PLAN.md)` (relative markdown link)
- **ADRs:** `[ADR-008: Template Versioning](../../decisions/ADR-008.md)`
- **Roadmap:** `[Q2 2025 Dashboard Redesign](../../ROADMAP.md#q2-dashboard)`
- **Dependency tables:** columns `| Blocker | Ticket | Status | ETA |`

## Verified marker

When `/planning-tools:plan-verify` passes a plan, it appends one line to the **context block** (not the end of the document):

```markdown
> **Verified:** 2026-05-11
```

This matches the existing bold-prefix callout convention and surfaces verification status near the top where it will be read first.

## Single-owner rule

When a rule, threshold, or convention is owned by another skill (e.g., a WCAG contrast ratio in a design-principles plugin), reference the owner — do not restate the rule. Example: `Apply WCAG 4.5:1 contrast (see visual-design-principles:accessibility-inclusive-design skill)`.

## Why these rules

- **Integer phases**: Decimal or letter-suffix phases drift into ad-hoc sub-phasing. Integer-only enforces real decomposition: when the architect wants `Phase 0.5`, the answer is to either fold it into `Phase 1` or promote it to its own `Phase 2`.
- **No sizing**: Effort estimates rot quickly and shift focus from "what" to "how long". Phases describe scope; effort is decided when the phase is opened in `/plan` mode.
- **Open Questions at top**: They block decisions. A skimmer who reads the first 30 lines must see blockers immediately.
- **Project-agnostic**: Ticket prefixes (CI-*, D2-*, OPS-*, AIA-*) are project conventions, not universal types. The plugin works in any codebase; section selection is trigger-based on what the work touches.
