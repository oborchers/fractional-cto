---
name: progress-methodology
description: This skill should be used when authoring or applying a progress update via the planning-tools plugin (the /planning-tools:plan-progress command). Codifies the dense-paragraph progress style, sub-markers (Piggybacked / Verification / Out of scope / Shipped), entry-key marker convention, SHA-tracking idempotency rule, three-way entry detection (no / in-flight / completed), comment-fetch policy (all, no cap), and the read-only source adapter + read-write destination adapter contracts (v1: markdown file, Linear comment, GitHub issue/PR comment).
version: 0.2.0
---

# Progress Methodology

A **progress entry** is one durable record of what a single branch / PR / feature shipped or is in the process of shipping. The plugin's `/planning-tools:plan-progress` command synthesizes these entries from the working tree, git log, the matching master plan, and optionally a source ticket. The format is **opinionated and dense**: one paragraph per branch, narrative prose, evidence-rich.

This skill is read by:
- the `/planning-tools:plan-progress` command's inline composition routine (which loads this skill to learn the style spec — no separate agent)
- the `/planning-tools:plan-progress` command (to learn the adapter contracts + three-way detection rule)
- the `plan-verifier` agent and other auditors (as the single owner of progress-related conventions)

## The dense-paragraph style

Every progress entry is **one paragraph per branch / PR**. Not bullets. Not headings per phase. One paragraph.

The paragraph captures, in this order:

1. **What** changed — the unit of work (`Branch <name> (N commits, ready to PR / shipped via PR #NNN)`), what it closes/addresses.
2. **Where** it changed — file paths, ADR refs, commit short-SHAs in the prose; key symbols cited with `path:line` when the reader needs to locate them.
3. **Why** it changed — root cause (for bug fixes), design rationale (for features), or motivating constraint (for refactors). This is the load-bearing part — surface design pivots and the *reason* a choice was made, not just the choice.
4. **Verification** — explicit gates that passed (typecheck / lint / N tests / live PROD verification / etc.), as a single sub-marker at the end.

The reader skimming six months later needs to understand the *reason* behind the design without reading the diff. Volume of prose is acceptable; vagueness is not. Names, paths, SHAs, and counts go in the entry; "we cleaned up some things" does not.

## Sub-markers

Inside the dense paragraph, certain inline section breaks have **bolded prefix labels**. The synthesizer emits them in this order, omits any whose content is empty:

| Marker | Used when |
|---|---|
| `**Piggybacked:**` | Commits touched files outside any plan-phase scope. One mini-paragraph per piggyback unit (a feature, refactor, or fix not in the original plan). |
| `**Piggybacked?:**` | The synthesizer is unsure whether commits map to a phase scope or are out-of-plan. The user resolves at the apply gate. |
| `**Verification:**` | The gates the work passed (typecheck, lint, test counts, e2e, manual PROD verification, etc.). Always present on entries that touched code. |
| `**Out of scope:**` | Things deferred or explicitly rejected. Often references a follow-up ticket or "tracked in memory for a future sweep." |
| `**Operational rollout:**` | Used when the change involves secrets, infra flips, or staged environment promotion. Mirrors the user's existing convention. |
| `**Rollback:**` | Used when the change has notable rollback implications worth recording. |

Sub-markers are **inline** — they don't break the entry into separate top-level sections. They sit inside the same paragraph, separated by sentence breaks. This keeps the entry scannable as a single unit.

## The Shipped marker

A completed entry begins with:

```
**Shipped <YYYY-MM-DD> via PR #<N>.**
```

and the entry's heading gains a trailing `✅`:

```
## <ticket-id-or-slug>: <one-line synopsis> ✅
```

The synthesizer applies both markers **only** when invoked with `--final`. Without `--final`, the entry stays in "in-flight" form (no shipped prefix, no `✅` on the heading).

PR numbers are auto-fetched via `gh pr list --head <branch> --json number,url` when GitHub is available. If no PR exists at `--final` time, the synthesizer emits `**Shipped <YYYY-MM-DD>.**` without the `via PR` clause.

## Entry-key marker (HTML comment)

Every entry starts with a stable HTML comment marker so the destination adapter can find it deterministically — no fuzzy heading matching:

```html
<!-- planning-tools:plan-progress entry-key:<branch-slug> -->
```

`<branch-slug>` is the current branch name normalized the same way as `/planning-tools:plan-tick` normalizes plan basenames (strip `feature/`, `fix/`, `chore/`, `bugfix/`, `hotfix/` prefixes; lowercase; replace `_` and `/` with `-`).

When updating an existing entry, the destination adapter locates it by exact marker match. When creating a new entry, the synthesizer emits the marker as the first line of the body.

For Linear / GitHub comments, the marker lives at the top of the comment body (HTML comments render invisibly in Linear and GitHub markdown).

## SHA-tracking convention

Every commit narrated in an entry is cited by its short SHA (`a1b2c3d`) somewhere in the prose. This is both reader-facing (cite the commit you mean) and machine-checkable (the synthesizer scans an existing entry for short SHAs to determine what's already covered).

The synthesizer's idempotency rule:

1. Read the existing entry body (string, may be empty).
2. Extract all tokens matching `\b[0-9a-f]{7,12}\b` — the **covered SHA set**.
3. From `git log <merge-base>..HEAD --pretty=format:'%h'`, build the **branch SHA list**.
4. **New commits** = branch SHAs ∉ covered SHA set.
5. If new commits is empty and the entry already has `✅`, return verdict `NO_CHANGES` and exit before writing.
6. Otherwise, narrative for new commits gets appended/woven into the existing entry; already-cited SHAs in the existing prose are **preserved verbatim** in their original sentences (don't re-anchor them).

This makes per-phase updates work: ship phase 3 commits → run `/plan-progress` → entry grows by the phase 3 paragraph + its SHA citations; phases 1 and 2 prose is preserved as-is.

## Three-way entry detection

When `/planning-tools:plan-progress` runs, the destination adapter looks up the current branch's entry-key. Three outcomes drive the flow:

| Detection result | Synthesizer behavior | Apply gate |
|---|---|---|
| **No match** | Create a new entry from scratch (commits + plan + style exemplars). | Binary `AskUserQuestion`: `"Append to <destination>"` / `"Discard"`. |
| **Match, no `✅`** (in-flight) | Read existing entry, identify new commits via SHA-tracking, extend prose in place. Old prose preserved; new commits drive new sentences. | Show diff (old vs new body), binary `AskUserQuestion`: `"Update <destination>"` / `"Discard"`. |
| **Match, has `✅`** (completed) | Could mean either "re-narrate the completed work" or "this is a new entry on the same branch slug." Ambiguous. | 3-option `AskUserQuestion`: `"Refresh completed entry"` / `"Create new entry"` / `"Cancel"`. |

The third case is the only place `/plan-progress` uses a 3-option question (still well under the 4-option cap — see `[[askuserquestion-4option-cap]]`).

## Piggyback detection

The synthesizer compares the set of files touched by the branch's commits (from `git diff <merge-base>..HEAD --name-only`) against the master plan's per-phase Scope cells. Files not covered by any phase scope are candidates for piggyback narration.

Two levels of confidence:

- **High confidence** (file is clearly outside every phase scope) → `**Piggybacked:**` section.
- **Low confidence** (file *could* be tangentially related to a phase scope) → `**Piggybacked?:**` (question-mark variant). The user resolves at the apply gate by editing the entry or accepting as-is.

If no master plan matched the branch (the `/plan-progress` command warned and proceeded with empty plan input), **omit the Piggybacked marker entirely** — piggyback is undefined without a plan reference.

## Source adapter contract (read-only)

Source adapters fetch ticket content for use as planning input. They are **read-only**.

```
fetch_source(identifier) → { title, body, comments[], status, url }
```

Where `comments[]` is an array of `{ author, timestamp, body }` in chronological order.

### v1 source adapters

| Provider | Identifier patterns | Implementation |
|---|---|---|
| `linear` | `[A-Z]{2,6}-\d+` (e.g., `AIA-1234`), `https://linear.app/<org>/issue/<ID>/...` | `mcp__linear-server__get_issue` → title, body, status, url; `mcp__linear-server__list_comments` → comments[] chronologically. |
| `github` | `https://github.com/<owner>/<repo>/issues/<N>`, `https://github.com/<owner>/<repo>/pull/<N>`, `<owner>/<repo>#<N>` | `gh issue view <N> --repo <owner>/<repo> --json title,body,state,url,comments` (or `gh pr view` if PR). |

### Comment fetch policy

**All comments, no cap.** Every comment on the ticket is fetched verbatim and included in `comments[]` (chronological order, with author + timestamp + body per entry). No truncation. No summarization. No "most-recent N" heuristic.

Rationale: tickets routinely encode load-bearing decisions in older comments — acceptance criteria revisions, design pivots, sign-offs, scope cuts. Silent truncation would silently drop them.

Known tradeoff: a 100+ comment thread is non-trivial context spend. Accepted on the basis that planning is the one place where ticket fidelity matters most. The synthesizer and architect agents are responsible for being selective about what they cite *from* the comments — the adapter pre-filters nothing.

If the relevant MCP / CLI is unavailable (Linear MCP not loaded, `gh` not on PATH), the adapter **fails loudly** rather than returning a partial result. The orchestrating command surfaces the failure to the user.

## Destination adapter contract (read-write)

Destination adapters find, create, and update progress entries. They are the only place `/plan-progress` performs writes.

```
find_existing_entry(identifier) → { id, body } | null
create_entry(content) → { id, url }
update_entry(id, new_body) → { url }
mark_shipped(id, { date, pr_url, pr_number }) → { url }
```

`identifier` for find/create is the entry-key (branch-slug). For Linear / GitHub destinations, the identifier composite is `(ticket-id, entry-key)` — the comment is posted on the ticket but uniquely identified within that ticket by its entry-key marker.

### v1 destination adapters

| Destination | Identifier | Implementation |
|---|---|---|
| `markdown` | A file path the **user chooses** + entry-key. The plugin never hardcodes the path. Common conventions: `PROGRESS.md` at repo root, `docs/PROGRESS.md`, `context/PROGRESS.md`, `notes/progress.md`. The discovery probe in `/planning-tools:plan-progress` recommends an existing match if found; otherwise the user supplies the path via `--destination markdown:<path>`. | `find`: Read file, grep for marker line, capture the section from marker to next `## ` heading or EOF. `create`: prepend a new `## ` section at the top of the file (newest-first ordering). `update`: replace the section in place via Edit. `mark_shipped`: append `✅` to the heading and prepend the shipped prefix to the body. |
| `linear` | Ticket ID + entry-key | `find`: `mcp__linear-server__list_comments` on the issue; grep each comment body for marker. `create`: `mcp__linear-server__save_comment` with the marker as the first line. `update`: `save_comment` with the existing comment's `id` to overwrite. `mark_shipped`: `update_entry` with the shipped-prefixed body. |
| `github` | Issue/PR number + entry-key | `find`: `gh issue view --comments --json comments` (or PR variant); grep for marker. `create`: `gh issue comment <N> --body <text>`. `update`: GitHub doesn't allow editing comments via `gh` CLI directly without the comment node ID — use `gh api repos/<owner>/<repo>/issues/comments/<comment-id> -X PATCH -f body=<text>`. `mark_shipped`: same as update with shipped-prefixed body. |

All adapters preserve the entry-key marker as the literal first line of the entry body. All adapters treat the body string as opaque — markdown formatting flows through unchanged.

If a destination adapter's underlying MCP/CLI is unavailable, `/plan-progress` fails loudly — never silently downgrades to a different destination.

## Single owner of the conventions

Per the CLAUDE.md single-owner rule: every concept named in this skill (sub-markers, entry-key format, SHA-tracking algorithm, three-way detection, piggyback levels, adapter contracts, comment-fetch policy) is **owned here** in full. Other planning-tools files reference this skill rather than restating the rules.

The `master-plan-methodology` skill is the owner for plan structure, Open Questions placement, integer phases, etc. — not duplicated here. The two skills cross-reference but never contradict.

## Configuration file

Per-project progress configuration lives at `.claude/planning-tools.local.md` (project-relative; gitignored). YAML frontmatter + markdown body, per the `plugin-dev:plugin-settings` pattern.

Recommended schema:

```yaml
---
progress_destination: markdown    # or "linear" or "github"
progress_destination_id: <your-progress-path>  # for markdown, a path you choose; for linear/github, a ticket/issue ref. Never assume context/, docs/, or any directory — let the user decide.
ticket_provider: linear           # or "github" or "none" — drives auto-detection in /plan-progress and /plan-master / /plan-context
ticket_prefix: AIA                # optional regex anchor for Linear ID auto-detection from branch names
---

# Notes

Free-form notes about this project's progress conventions, if any.
```

`/plan-progress` writes this file the first time the user picks a destination via `AskUserQuestion`. Subsequent runs read the file silently.

To switch destinations later, the user edits the file directly, or runs `/plan-progress --destination <type>:<id>` for a one-off override (without overwriting saved settings).

## Cross-references

- `[[master-plan-methodology]]` — owns plan structure, phase numbering, status emoji.
- `[[plan-verification-checklist]]` — owns plan-audit dimensions (does not touch progress entries).
- `[[askuserquestion-4option-cap]]` — owns the binary-fallback pattern for dynamic-length user choices.
- `[[plugin-settings]]` (plugin-dev plugin) — owns the `.claude/<plugin>.local.md` file format.
