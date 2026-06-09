---
name: master-plan-methodology
description: This skill should be used when authoring, reviewing, or modifying a multi-phase master planning document via the planning-tools plugin (especially the /plan-master and /plan-verify commands). Codifies the universal core sections, trigger-based optional sections, integer-only phase numbering, Open Questions placement, one-PR-per-plan rule, status conventions, evidence attribution, callouts, cross-reference formats, the v0.3.0 list-shape mandate (phases and questions are heading + bulleted list, never markdown tables), the v0.3.1 per-phase TL;DR requirement (1–3 sentence what/why summary under each phase heading for glance-ability), the v0.3.2 plain-bullet scope shape (`- <action>` items, no `- [ ]` checkboxes — the phase status emoji is the sole tick signal), and the v0.3.3 context-block shape (a plan-level `**TL;DR:**` + a bulleted metadata list instead of a `>` blockquote; legacy blockquote blocks accepted silently). Project-agnostic — no ticket-prefix or plan-type taxonomy.
version: 0.3.3
---

# Master Plan Methodology

A **master plan** is a long, multi-phase planning document that decomposes a topic, ticket, or roadmap item into actionable phases. Each phase maps 1:1 to a Claude Code `/plan`-mode session. The master plan is the durable artifact; the per-phase plans in `~/.claude/plans/<slug>.md` are ephemeral.

This skill codifies the **format and conventions** every master plan must follow. The `plan-master-architect` agent writes plans to this spec; the `plan-verifier` agent audits plans against it.

## The 5-step workflow

The plugin orchestrates master plans through five steps:

1. **`/planning-tools:plan-context [topic | path] [--domains a,b,c]`** — Pre-load context. Stage 1 Triage proposes domains, Stage 2 Confirm checks them with the user, Stage 3 dispatches parallel Explore agents (one per confirmed domain), Stage 4 verifies findings with direct Reads. Emits a scope report. **NO plan file written.**
2. **`/planning-tools:plan-master [topic] [--context <report-path>]`** — Draft the master plan. Reuses a fresh `/planning-tools:plan-context` report if `--context` is passed; otherwise runs the same Triage + Confirm + Explore + Verify pre-flight internally. Then synthesizes the multi-phase plan via the `plan-master-architect` agent (opus). Writes to a project-local path.
3. **`/planning-tools:plan-verify <path>`** — Audit the drafted plan. Dispatches the `plan-verifier` agent against the `plan-verification-checklist` skill, presents Critical/Important/Suggestion findings, and (on user approval) appends a `- **Verified:** YYYY-MM-DD` bullet to the context block (a `> **Verified:**` line on legacy blockquote plans).
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
2. **Plan-level TL;DR** — `**TL;DR:**` on the first non-blank line under the title: 2–4 sentences capturing what the whole plan does and why. See "Plan-level TL;DR + context block shape" below (v0.3.3+).
3. **Context block** — a plain bullet list of metadata: `- **Ticket:** <url>` (optional, when a ticket source resolved), `- **Ticket(s):** …`, `- **PRD / Source:** …`, `- **Evidence:** …`, `- **Depends on:** …`, `- **Constraints:** …`. **No blockquote (v0.3.3+).**
4. **Open Questions** — unordered list of blocking questions with `**Q<N> — <one-line question>:**` prefix, **placed immediately after the context block** (not at the end). **No tables.**
5. **Resolved Questions** — unordered list with the same `**Q<N> — <question>:** <resolution>` shape (may be empty). **No tables.**
6. **Implementation Phases** — one `### Phase <N>: <verb-led name> <emoji>` H3 heading per phase, followed by a required `**TL;DR:**` callout (1–3 sentences, what + why), then a plain unordered bulleted list (`- <action>` items) as Scope. **No tables. No `- [ ]` checkboxes (v0.3.2+).** See the "Per-phase TL;DR" section below for the v0.3.1 TL;DR requirement and "Plain-bullet scope shape" below for v0.3.2+.
7. **Design Principles** — numbered list of opinionated rules
8. **What's NOT in <TOPIC> (and why)** — explicit out-of-scope items with reasoning

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

Each phase heading ends with one of these emoji, separated from the phase name by exactly one space:

- `⏳` Pending
- `🚧` In Progress
- `✅` Done
- `❌` Blocked

Example: `### Phase 3: Wire MutationCache.onError through shouldInvalidateSession ⏳`.

The emoji is the **last token** of the heading line. `/planning-tools:plan-tick` flips this emoji to `✅` when the phase is verdicted ACHIEVED. Strikethrough (`~~Phase 1: …~~`) on completed phase headings is allowed but not required.

The **phase heading emoji is the sole tick signal** (v0.3.2+). Per-bullet checkbox state is no longer used — see "Plain-bullet scope shape" below.

## Per-phase TL;DR (non-negotiable, v0.3.1+)

Every phase **must** include a `**TL;DR:**` callout — 1–3 sentences capturing what the phase does and why — placed on the **first non-blank line under the heading**, before the first `- ` scope item.

**Shape:**

```markdown
### Phase 3: Wire MutationCache.onError through shouldInvalidateSession ⏳

**TL;DR:** Add a session-classifier branch at the top of `MutationCache.onError` so real session-expired mutations trigger the modal instead of a silent toast. Needed because the existing path only classified queries — mutations 401'd into a dead-end UX.

- <scope item>
- **Exit criteria:** …
```

**Content rules:**

- **First sentence:** what the phase does (the verb action).
- **Subsequent sentence(s):** why — the motivation, the constraint, the problem it addresses.
- **Length:** 1–3 sentences as guidance. The verifier checks presence, not length.
- **No file paths, line numbers, or test counts** in the TL;DR. Those belong in the scope checklist below it.
- **No verdicts or exit criteria** in the TL;DR. Those are scope items.
- Inline markdown allowed (code spans, bold for emphasis, links to ADRs or tickets).

**Why:** master plans accumulate 30–60 bullets across 6–10 phases. Without a glance-able summary, the reader has to scan every bullet to grasp what each phase does. With a `**TL;DR:**` per phase, scrolling the plan top-to-bottom reading only the bolded TL;DR lines gives a 60-second overview of intent — useful for re-orienting after time away, for reviewers, and for the "did I forget anything?" pass before opening the PR.

**Severity if missing:** `plan-verifier` flags missing TL;DRs as **Important** — readability gap, not correctness gap. Existing v0.3.0 plans without TL;DRs continue to tick, get progress entries, and walk Open Questions. The verifier nudges; it does not block.

**Tooling transparency:** `/plan-tick`, `/plan-progress`, and `/plan-open-questions` all read per-phase scope as the line region under each heading. The TL;DR is just one more line in that region — invisible to them. No parser updates needed.

## Plan-level TL;DR + context block shape (non-negotiable, v0.3.3+)

The plan opens with a **plan-level TL;DR** followed by a **bulleted context block** — not a `>` blockquote.

**Shape:**

```markdown
# <Title>: <one-line synopsis>

**TL;DR:** Add a session-classifier branch so real session-expired mutations trigger the modal instead of a silent toast. The existing path only classified queries — mutations 401'd into a dead-end UX, blocking the StudSek rollout.

- **Ticket:** https://linear.app/acme/issue/SA-2241
- **Ticket(s):** SA-2241 — [StudSek Rollout]
- **PRD / Source:** Linear SA-2241 body + worker findings
- **Evidence:** Live read-only SF probe 2026-06-08 (`scripts/sf-probe.ts`)
- **Depends on:** SA-2241 Chatter comment subsystem (`src/.../comment.ts` write path)
- **Constraints:** ADR-15/25/28/34/47/53; no DB schema change

---

## Open Questions
```

**TL;DR content rules** (mirror the per-phase TL;DR):

- First sentence = what the plan does; subsequent sentence(s) = why (the motivation, the problem, the blocker it clears).
- 2–4 sentences as guidance. The verifier checks presence, not length.
- **No file paths, line numbers, or test counts** — those belong in the context bullets and phases.
- Inline markdown allowed (code spans, bold, links to ADRs/tickets).

**Context-block bullets:** each metadata field is a `- **Label:** value` bullet. `- **Ticket:** <url>` is the first bullet and is present only when `/planning-tools:plan-master` resolved a ticket source (folds in the old above-the-block nav callout). The remaining fields (Ticket(s), PRD/Source, Evidence, Depends on, Constraints) follow. `/planning-tools:plan-verify` appends a trailing `- **Verified:** <date>` bullet on PASS.

**Why:** the old `>` blockquote context block stacked six-plus bold-prefixed lines of wrapping prose into an unscannable wall that readers skimmed past. A plan-level TL;DR gives the elevator pitch first; bullets make each metadata field individually scannable.

**Severity if the plan-level TL;DR is missing:** `plan-verifier` flags it **Important** (readability gap, not correctness) — same as the per-phase TL;DR rule. Plans without it still tick, verify-to-PASS-reachable, and walk Open Questions.

**Legacy blockquote shape (transition).** Plans authored before v0.3.3 use a `> **Ticket(s):** …` / `> **Constraints:** …` blockquote context block (with `> **Verified:** …`). These continue to parse and **pass verification with no finding** — the goal is reducing noise, not creating it. `/planning-tools:plan-verify` appends the Verified marker as a `>` line on these legacy plans. New plans use the TL;DR + bullets shape.

## No tables for phases / questions (non-negotiable, v0.3.0+)

The Implementation Phases, Open Questions, and Resolved Questions sections **must not** use markdown tables. Use:

- `### Phase <N>: <name> <emoji>` H3 headings with `- ` bulleted scope items for phases (v0.3.2+ shape — plain bullets, no `- [ ]` checkboxes).
- `- **Q<N> — <question>:**` bulleted lines for Open and Resolved Questions (free-form prose follows the colon).

**Why:** Markdown tables force each cell onto a single line — phase Scope cells became 1500–2500 char escaped-prose walls that cannot be read without horizontal scroll, cannot contain native lists or code blocks, and consume tokens on pipe-escape overhead. Headings + lists restore native markdown affordances.

**Narrow-cell tables elsewhere are still allowed.** Architecture matrices, Code-Changes-by-file × phase coverage tables, Dependency tables, Cost summaries, etc., remain in table form — the ban is scoped to phases / questions, where wide cells are the failure mode.

The `plan-verifier` agent flags any master plan that uses tables for phases or questions as a **Critical** finding. The `/planning-tools:plan-tick` command supports the legacy v0.2.x table shape during a transition window so existing plans keep working (it emits a one-line note when it falls through to the legacy parser), but newly-authored plans must use the v0.3.0 shape.

## Plain-bullet scope shape (non-negotiable, v0.3.2+)

Phase scope is a plain `- <action>` unordered list — **no `- [ ]` checkboxes**. The phase **status emoji** on the heading (`⏳ 🚧 ✅ ❌`) is the sole tick signal; per-bullet "done" state is not tracked because in practice it is not maintained.

**Bold-prefix scope items still work unchanged:** `- **Tests:** …`, `- **Exit criteria:** …`, `- **Note:** …` — the bold label was always the semantic anchor; the bracket was decoration.

**Legacy checkbox shape (transition).** Plans authored under v0.3.0 / v0.3.1 may use `- [ ]` / `- [x]` scope items. These continue to parse — `/planning-tools:plan-tick`'s heading parser strips the optional `[ ]`/`[x]` prefix before evidence extraction. No verifier finding is emitted for the legacy shape; the goal is reducing noise, not creating it. New plans should use plain `- ` bullets.

## Skeleton template

```markdown
# <Title>: <one-line synopsis>

**TL;DR:** <2–4 sentences: what this plan does and why. The elevator pitch a reader gets before any metadata or phases.>

- **Ticket:** <linear-or-github-url>  <!-- optional; only if /plan-master got a ticket source -->
- **Ticket(s):** <Linear/Jira refs or n/a>
- **PRD / Source:** <doc paths>
- **Evidence:** <transcript YYYY-MM-DD speaker quote | bug report | research path:line>
- **Depends on:** <ticket> (<specific artifact>)
- **Constraints:** <viewport, env, etc.>

---

## Open Questions

- **Q1 — <one-line question>:** <free-form context. Blocking: yes/no.>
- **Q2 — <one-line question>:** <context>

## Resolved Questions

- **Q1 — <question>:** <resolution prose, no length limit>
- **Q2 — <question>:** <resolution>

## Implementation Phases

### Phase 1: <verb-led phase name> ⏳

**TL;DR:** <One sentence stating what the phase does.> <Optional 1–2 sentences explaining why — motivation, constraint, gap addressed.>

- <Scope item: action + concrete file path + line range>
- <Scope item with `code spans` and **bolded emphasis** as needed>
- **Tests:** <test files to add/update, named cases>
- **Exit criteria:** <what proves the phase is done — green checks, behavior verified>

### Phase 2: <verb-led phase name> ⏳

**TL;DR:** <What + why, 1–3 sentences.>

- …
- **Exit criteria:** …

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

- `**TL;DR:** …` — required under every `### Phase` heading (v0.3.1+): 1–3 sentences capturing what the phase does and why. See "Per-phase TL;DR" above for the full rule.
- `**Decision:** …` — a settled choice
- `**Rationale:** …` — the reasoning for a Decision
- `**Risk:** …` — a known risk
- `**Mitigation:** …` — how the Risk is addressed
- `**Note:** …` — informational aside

Blockquotes (`>`) are reserved for **invariants and constraints** (e.g., `> Templates are immutable after first publish`). The top-of-file context block is **no longer a blockquote** (v0.3.3+) — it is a plan-level `**TL;DR:**` + a bulleted metadata list. See "Plan-level TL;DR + context block shape" above.

## Cross-reference conventions

- **Tickets:** `[CI-15](../CI-15-PLAN.md)` (relative markdown link)
- **ADRs:** `[ADR-008: Template Versioning](../../decisions/ADR-008.md)`
- **Roadmap:** `[Q2 2025 Dashboard Redesign](../../ROADMAP.md#q2-dashboard)`
- **Dependency tables:** columns `| Blocker | Ticket | Status | ETA |`

## Verified marker

When `/planning-tools:plan-verify` passes a plan, it appends one entry to the **context block** (not the end of the document), surfacing verification status near the top where it is read first:

- **v0.3.3+ plans** (bulleted context block): a trailing bullet at the end of the context bullet list:
  ```markdown
  - **Verified:** 2026-05-11
  ```
- **Legacy blockquote plans:** the old `> **Verified:** 2026-05-11` line after the last `>` line of the block.

## Single-owner rule

When a rule, threshold, or convention is owned by another skill (e.g., a WCAG contrast ratio in a design-principles plugin), reference the owner — do not restate the rule. Example: `Apply WCAG 4.5:1 contrast (see visual-design-principles:accessibility-inclusive-design skill)`.

## Why these rules

- **Integer phases**: Decimal or letter-suffix phases drift into ad-hoc sub-phasing. Integer-only enforces real decomposition: when the architect wants `Phase 0.5`, the answer is to either fold it into `Phase 1` or promote it to its own `Phase 2`.
- **No sizing**: Effort estimates rot quickly and shift focus from "what" to "how long". Phases describe scope; effort is decided when the phase is opened in `/plan` mode.
- **Open Questions at top**: They block decisions. A skimmer who reads the first 30 lines must see blockers immediately.
- **Project-agnostic**: Ticket prefixes (CI-*, D2-*, OPS-*, AIA-*) are project conventions, not universal types. The plugin works in any codebase; section selection is trigger-based on what the work touches.
