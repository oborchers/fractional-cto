---
description: "Compress a markdown file to reduce token usage — lossless (structural) or lossy (semantic) modes with section-by-section review"
argument-hint: "<file-path> [--lossless] [--auto]"
disable-model-invocation: true
---

Compress the specified markdown file using the `markdown-compression` skill. The goal is to reduce token usage while preserving the information an LLM needs.

Follow this process exactly:

## Step 1: File Validation

Read the file specified in `$ARGUMENTS`. If no file was provided, use `AskUserQuestion` to ask the user which file to compress.

Verify:
- File exists and is readable
- File is markdown (`.md` extension)
- File is not empty

If the file has YAML frontmatter, note it — frontmatter must be preserved exactly.

## Step 2: Mode Selection

If `--lossless` was passed in arguments, use lossless mode. Otherwise, use `AskUserQuestion` to ask:

- **Lossy (recommended)** — semantic compression with compressor-reviewer loop. Maximum token reduction.
- **Lossless** — structural optimization only. Zero semantic change.

If `--auto` was passed in arguments, enable auto-approve mode (skip per-section user review). Otherwise, per-section review is the default — but the user will be offered the option to switch to auto-approve after the first section.

## Step 3: Pre-Analysis

Read the full file and analyze its structure:

1. Parse the heading hierarchy (identify all `#`, `##`, `###`, etc.)
2. Split the file into sections at the highest sensible heading level (typically `##`)
3. For each section, count approximate tokens (words * 1.3)
4. Flag any structural issues:
   - Skipped heading levels (e.g., `#` → `###`)
   - Sections over ~500 tokens (candidates for attention)
   - Empty sections
   - Duplicate content across sections

Present the structural analysis as a table:

```
| # | Section | Tokens | Notes |
|---|---------|--------|-------|
| 1 | Overview | ~130 | |
| 2 | Configuration | ~340 | |
| 3 | Deployment | ~520 | Large section |
| 4 | Testing | ~0 | Empty |
```

Show the total token count. Then proceed to compression.

## Step 4: Section-by-Section Compression

Process each non-empty section in order. For each section:

### 4a: Compress

Dispatch the `section-compressor` agent with:
- The section's original text
- The compression mode (lossless or lossy)
- The section heading
- Adjacent section headings for context

### 4b: Review (lossy mode only)

If in lossy mode, dispatch the `compression-reviewer` agent with:
- The original section text
- The compressed section text
- The mode

If the reviewer flags critical issues, incorporate the reviewer's suggested restorations into the compressed version before presenting to the user.

### 4c: Present and Decide

**If auto-approve is active**, skip user review — go directly to 4d (Write Back). Still show a brief one-line status per section so the user can follow progress:

```
Section [N]/[total]: [heading] — ~X → ~Y tokens (-Z%)
```

If the reviewer flagged critical issues in lossy+auto mode, incorporate the reviewer's suggested restorations automatically (the reviewer's judgment acts as the quality gate instead of the user).

**If auto-approve is NOT active**, show the user the diff:

```
**Section: [heading]**
Original (~X tokens) → Compressed (~Y tokens) | -Z%

[Show the compressed version]

Changes: [brief list of what changed]
```

If the reviewer flagged and the compressor's output was adjusted, note: "Reviewer caught: [what was restored]"

Use `AskUserQuestion` for the user's decision:
- **Approve** — accept the compressed version
- **Skip** — keep the original section unchanged
- **Edit** — user provides custom text for this section

If the user chooses Edit, accept their replacement text for the section and continue.

**After the first section review**, offer to switch to auto-approve for the remaining sections. Use `AskUserQuestion`:

- **Continue section-by-section** — keep reviewing each section individually
- **Auto-approve remaining** — compress all remaining sections without further review (reviewer still runs in lossy mode)

This offer appears once, after section 1. If the user chooses section-by-section, do not ask again.

### 4d: Write Back Immediately

**After every decision (or auto-approval), immediately write the result to the file.** Do not defer writes to the end.

- **Approve / Auto-approve:** Use the `Edit` tool to replace the original section text with the compressed version in the file.
- **Skip:** No edit needed — the original text stays.
- **Edit:** Use the `Edit` tool to replace the original section text with the user's custom text.

This ensures:
- Progress is saved incrementally — if the session crashes, approved sections are already written
- The user can run `git diff` at any point to see cumulative progress
- No risk of losing work from a failed final assembly

**Important:** After each `Edit`, re-read the file to get the updated content before processing the next section. Section boundaries may shift as earlier sections change length. Use the heading text (which is preserved) to locate the next section reliably.

## Step 5: Results

After all sections are processed, show the compression summary:

```
## Compression Complete

| Metric | Value |
|--------|-------|
| Original | ~X tokens |
| Compressed | ~Y tokens |
| Reduction | Z% |
| Sections modified | A of B |
| Mode | lossless/lossy |
```

The file has already been updated in-place throughout Step 4. Inform the user: "All changes written. Use `git diff` to review or `git checkout -- <file>` to revert."

## Mandatory Use of AskUserQuestion

**Every user decision point MUST use the `AskUserQuestion` tool.** Never ask for decisions via inline text. The interactive selector provides a consistent UX.

### Main Conversation Owns All User Interaction

`AskUserQuestion` must be called from **this command** (the main conversation), never from subagents. The `section-compressor` and `compression-reviewer` agents handle compression and review — they return results. This command presents those results and calls `AskUserQuestion` for every decision gate.

**Pattern:** dispatch compressor agent → receive compressed section → dispatch reviewer agent → receive review → present diff → call `AskUserQuestion` (approve/skip/edit) → **write to file immediately** → next section.

### Decision Points

Use `AskUserQuestion` at:
- File selection (if no argument)
- Mode selection (if no `--lossless` flag)
- Per-section approval (approve/skip/edit) — unless auto-approve is active
- Auto-approve offer after first section (unless `--auto` flag was passed)
