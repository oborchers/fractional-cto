---
name: plan-verification-checklist
description: This skill should be used by the plan-verifier agent and the /plan-verify command to audit a drafted master plan against a fixed checklist. Covers universal-core completeness, trigger-based section-coverage gaps, phase actionability, integer phase numbering enforcement, dependency traceability, citation resolution, callout/evidence convention compliance, Open Questions placement, and the one-PR-per-master-plan rule. Single-owner of the audit checklist.
version: 0.2.1
---

# Plan Verification Checklist

This skill codifies the audit performed by `/plan-verify` and the `plan-verifier` agent. It is the single owner of the checklist; the command and agent both reference it rather than duplicating rules.

The checklist applies to any master plan written under the `master-plan-methodology` skill. Findings are graded **Critical**, **Important**, or **Suggestion**.

## Severity guide

- **Critical** — the plan cannot be safely executed as written. Phase numbering violates the integer-only rule; required universal-core sections are missing; phases have no actionable scope (no file paths, no exit criteria); cited sources do not exist.
- **Important** — the plan can be executed but has gaps that will cause friction. Trigger-based optional sections are missing despite the work clearly touching that area (e.g., schema changes with no Rollback section); dependency notation is vague; Open Questions appear at the bottom instead of after the context block.
- **Suggestion** — the plan would benefit from polish. Bold-prefix callouts not used where they would help; cross-references use absolute paths instead of relative; status emoji inconsistent.

## Audit dimensions

### 1. Universal-core completeness

Verify every required section is present and in the prescribed order:

- [ ] **Title** (H1) with one-line synopsis
- [ ] **Quoted context block** (blockquote starting with `>`) containing Ticket(s), PRD/Source, Evidence, Depends on, Constraints
- [ ] **Open Questions** section, located **immediately after the context block** (Critical finding if at the bottom)
- [ ] **Resolved Questions** section (may be empty)
- [ ] **Implementation Phases** table
- [ ] **Design Principles** numbered list
- [ ] **What's NOT in <TOPIC> (and why)** section

Missing universal-core sections = **Critical**.

### 2. Section-coverage gaps (trigger-based)

For each trigger observed in the plan, check the corresponding optional section is present:

| If the plan mentions | Then it must include |
|---|---|
| SQL, schema changes, migrations, new tables/columns | **Data Model** / **Schema** AND **Rollback Procedure** |
| React components, UI changes, new screens/dialogs | **Component Architecture**, **UI States** or **Skeleton Screens**, **Manual QA Checklist** |
| Novel UI surfaces | **Visual Design — ASCII Mockups** |
| Multiple locales | **i18n** table |
| New analytics events or tracking | **Analytics** section |
| Cost-bearing infrastructure (e.g., cloud spend) | **Cost Summary** |
| Failure modes, dependencies, external risks | **Risks + Mitigations** |
| Manual deploy steps or post-merge ops | **Deployment Steps** |
| Production validation requirements | **Verification (post-merge / post-deploy)** |
| Production incident remediation | **Recovery for Affected Records** |
| File-level impact across phases | **Code Changes (file × phase)** |
| ≥5 design decisions referenced | **Design Decisions** table |
| Tests required for any phase | **Tests** breakdown |
| External prerequisites (other tickets) | **Prerequisites** |

Missing trigger-driven section = **Important**.

### 3. Phase actionability

Every phase row in the Implementation Phases table must have:

- [ ] A short imperative name (verb-led)
- [ ] A `Status` emoji (`⏳ 🚧 ✅ ❌`)
- [ ] Concrete **file paths** in scope (when the work touches code)
- [ ] **Exit criteria** or **definition of done** (in Scope cell or in a per-phase callout)
- [ ] **Test requirements** when tests are needed

Phases with vague scope ("update the UI", "improve performance") = **Critical**.

### 4. Integer phase numbering (non-negotiable)

Scan every "Phase" reference in the document:

- [ ] All phase numbers are positive integers (`1, 2, 3, …`)
- [ ] No decimals (`0.5`, `1.5`)
- [ ] No letter suffixes (`1A`, `2B`)
- [ ] No letter-only phases (`Phase A`, `Phase B`)
- [ ] No ranges (`Phase 0–5`)
- [ ] No `Sub-Phases` or `Implementation Sub-Phases` heading

Any violation = **Critical**.

### 5. Dependency traceability

The context block's `Depends on:` line, plus any inline `Depends on` references, must specify **the artifact** that creates the dependency, not just the ticket:

- ✅ `Depends on: CI-22 (src/features/cases/lib/sf-links.ts helpers + i18n key + ADR-28 amendment)`
- ❌ `Depends on: CI-22`

Vague dependencies = **Important**.

### 6. Citation resolution

Every evidence claim must be traceable:

- [ ] Transcripts cite **speaker + env + date + ticket + case-ref + verbatim quote**
- [ ] ADR references use `ADR-NN` or full path
- [ ] Code references use `<repo-relative-path>:<line>`
- [ ] Research docs use relative paths (no broken links)

Unresolvable or vague citations = **Important**. Fabricated citations (linked source does not exist) = **Critical**.

### 7. Callout / evidence convention compliance

Bold-prefix callouts must use the prescribed labels:

- [ ] `**Decision:** …` for settled choices
- [ ] `**Rationale:** …` for reasoning
- [ ] `**Risk:** …` for known risks
- [ ] `**Mitigation:** …` for risk responses
- [ ] `**Note:** …` for informational asides

Blockquotes (`>`) are used **only** for invariants/constraints and the top-of-file context block. GitHub-style `> [!NOTE]` admonitions are not used.

Misused callout labels = **Suggestion**.

### 8. Open Questions placement

- [ ] **Open Questions** appears immediately after the context block (i.e., before Implementation Phases)
- [ ] The section is **not** at the bottom of the document

If Open Questions is at the bottom = **Important**.

### 9. No sizing estimates

- [ ] No `Size` column in Implementation Phases
- [ ] No XS/S/M/L, T-shirt sizes, or time estimates anywhere in the plan

Sizing present = **Important** (will be deleted on next revision).

### 10. One PR per master plan

Scan every phase scope and every section other than `Release`:

- [ ] No `gh pr create` instructions inside a phase
- [ ] No "Open PR" / "Merge PR" / "Request review" instructions inside a phase
- [ ] No "Reviewer can sign off after this phase" or similar per-phase PR handoff
- [ ] No per-phase merges to `main`, `master`, or `develop`

Per-phase `git commit` and `git push` to the working branch are **allowed** — do not flag them.

Per-phase PR creation, merging, or review-request = **Critical**. The fix is to remove the per-phase PR prose and move it (if needed) into a single `Release` section at the bottom of the plan.

### 11. Status conventions

- [ ] `Status` column uses emoji from the set `⏳ 🚧 ✅ ❌`
- [ ] No raw text like "Pending" / "Done" instead of emoji (the column header is "Status", values are emoji)

Mixed conventions = **Suggestion**.

## Report format

The verifier emits findings in this exact shape:

```markdown
# Verification Report: <plan filename>

> Verified: <date>
> Plan path: <path>

## Critical findings

### <#>: <Short title>
- **Location:** <file>:<line>
- **Rule violated:** <which audit dimension>
- **Quote:** <verbatim excerpt>
- **Fix:** <concrete fix>

## Important findings

### <#>: <Short title>
- **Location:** <file>:<line>
- **Rule:** <dimension>
- **Why:** <impact>
- **Fix:** <concrete fix>

## Suggestions

### <#>: <Short title>
- **Location:** <file>:<line>
- **Note:** <polish improvement>

## Summary

| Severity | Count |
|---|---|
| Critical | <n> |
| Important | <n> |
| Suggestion | <n> |

**Verdict:**
- `PASS` — zero Critical, ≤ 2 Important. Safe to append `> **Verified:** <date>` to the context block.
- `FAIL` — any Critical or > 2 Important. Plan must be revised.

**Top 3 highest-impact fixes:**
1. …
2. …
3. …
```

## Mandatory Use of AskUserQuestion

The verifier agent does **not** call `AskUserQuestion` — it emits the report only. The main conversation (in `/plan-verify`) presents the report and calls `AskUserQuestion` to ask the user whether to append the `> **Verified:** YYYY-MM-DD` callout to the context block when the verdict is `PASS`.
