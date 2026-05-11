---
description: "Mark a master plan phase as ✅ done — updates the Status cell in the Implementation Phases table. Idempotent, status-cell-only edit."
argument-hint: "<phase-number> [path-to-plan]"
---

You are **marking a phase complete** in a master plan. The command edits exactly one cell — the `Status` cell of the named phase row — from `⏳`/`🚧`/`❌` to `✅`. Nothing else is modified.

**Input:** `$ARGUMENTS`

Parse arguments:
- First positional integer → the **phase number** to mark.
- Optional path → an explicit master plan file. If omitted, discover via path resolution.
- Non-integer phase values (e.g., `1a`, `A`) → reject and point at the integer-only rule in `master-plan-methodology`.

If no phase number was supplied, **do not** mark anything yet — first locate the plan (Step 2), then call `AskUserQuestion` with the current phase rows so the user picks.

---

## Step 1 — Resolve the plan path

If a path was supplied:
- Validate the file exists. If not, error with the path.

If no path was supplied:
- Run `git rev-parse --show-toplevel` to find the repo root. If not in a git repo, ask the user via `AskUserQuestion` whether to use the current working directory as the search root or abort.
- Glob `<root>/context/tickets/*.md`, then `<root>/docs/plans/*.md`, then `<root>/.claude/plans/master/*.md`. Filter to files containing the heading `## Implementation Phases`.
- **0 candidates:** error with the three searched paths and a hint to pass an explicit path.
- **1 candidate:** use it. Display the resolved path to the user.
- **2+ candidates:** call `AskUserQuestion` (single-select). Label each option with the plan filename and the count of pending phases (e.g., `CI-21-PLAN.md — 3 pending`). Mark the most-recently-modified entry with `(recent)`.

---

## Step 2 — Read and validate the plan

1. Read the plan file.
2. Find the `## Implementation Phases` heading. **Reject** `## Implementation Sub-Phases` or any other variant with an error pointing at the integer-only phase rule in `master-plan-methodology`.
3. Find the markdown table immediately after that heading.
4. Parse the table header. **Reject** if there is no `Status` column with this exact header text, and error:
   ```
   Plan does not conform to master-plan-methodology v0.2.1+ — the Implementation Phases table must include a Status column with emoji values (⏳ 🚧 ✅ ❌). See planning-tools:master-plan-methodology.
   ```
5. Parse the table rows. For each row, extract the Phase column value (trimmed) and the Status emoji.
6. If any phase value is non-integer (`1a`, `A`, `0.5`, ranges), error with the integer-only rule pointer — do not attempt to tick a malformed plan.

---

## Step 3 — Resolve the phase to tick

If a phase number was supplied as an argument:
- Look it up in the parsed rows. If not found, error with the list of phase numbers actually present.
- If the row's Status is already `✅`, report `Phase N already done in <path>. No changes.` and **stop** (idempotent).

If no phase number was supplied:
- Call `AskUserQuestion` with one option per pending row (Status not `✅`), labelled `Phase N — <name> [<current emoji>]`. Skip already-done rows.
- After the user picks, continue.

---

## Step 4 — Edit the Status cell

Use the **Edit tool** with the entire row line as `old_string` and the modified line (only the Status emoji replaced) as `new_string`. This anchors the edit on the full row to avoid accidentally matching a different row.

Example transformation:

```
old_string: | 2 | Cache primer | ⏳ | Wire ReadThroughCache.warm() into the startup hook |
new_string: | 2 | Cache primer | ✅ | Wire ReadThroughCache.warm() into the startup hook |
```

If the Edit fails because `old_string` matched multiple lines (shouldn't happen with full-row anchor, but defense in depth): error with a hint that the row appears duplicated and to fix the plan manually.

If the row spans multiple lines (cell contains embedded newlines that broke the table grammar): error with `Row N appears to span multiple lines; manually edit the Status cell.`

---

## Step 5 — Report

Output one concise line:

```
Marked Phase N done in <path>. <K> phase(s) remain.
```

Where `<K>` is the count of rows whose Status is still `⏳`, `🚧`, or `❌`.

If all phases are now `✅`, append: `All phases complete. Consider running /planning-tools:plan-verify to confirm and then opening the single PR per the Release section.`

---

## Mandatory Use of AskUserQuestion

The main conversation owns all user interaction.

- **Plan discovery** (Step 1) — when 2+ candidate plans exist or when not in a git repo and no path was supplied.
- **Phase selection** (Step 3) — only when no phase number was passed as argument.

This command has no subagent dispatch. It runs entirely in the main conversation, like `/planning-tools:plan-delete`.

## Notes

- This command **only** writes the Status cell. It does not commit, push, PR, modify the Name cell (no strikethrough), or touch any other section.
- The command is **idempotent**: marking an already-done phase is a no-op.
- The command only works on plans conforming to `master-plan-methodology` v0.2.1+ (integer phases, Status column with emoji values). Legacy plans require manual editing or one-time migration to the canonical format.
