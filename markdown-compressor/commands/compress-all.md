---
description: "Recursively find and compress all matching markdown files in a repository — auto-approve mode with batched processing"
argument-hint: "<filename> [--lossless]"
disable-model-invocation: true
---

Recursively find and compress all files matching the given filename using the `markdown-compression` skill. Always runs in auto-approve mode with batched section processing.

Follow this process exactly:

## Step 1: Discover Files

Use the Glob tool to search for `**/<filename>` in the current working directory, where `<filename>` is the argument from `$ARGUMENTS` (e.g., `CLAUDE.md`).

If no filename was provided, use `AskUserQuestion` to ask which filename to search for (e.g., `CLAUDE.md`, `ARCHITECTURE.md`, `TREE.md`).

If no files are found, inform the user and stop.

## Step 2: Confirm File List

For each discovered file, read it and count approximate tokens (words * 1.3).

Present the file list:

```
| # | File | Tokens | Sections |
|---|------|--------|----------|
| 1 | ./CLAUDE.md | ~850 | 12 |
| 2 | ./src/CLAUDE.md | ~320 | 5 |
| 3 | ./supabase/CLAUDE.md | ~1,200 | 18 |

Total: ~X tokens across N files.
```

Use `AskUserQuestion` to confirm:
- **Compress all** — process every file in the list
- **Exclude some** — let the user specify files to skip (then confirm the reduced list)

## Step 3: Determine Mode

If `--lossless` was passed in arguments, use lossless mode for all files. Otherwise, default to **lossy** mode (no question needed — lossy is the recommended default for batch operations).

## Step 4: Process Each File

For each file in the confirmed list, in order:

### 4a: Announce

Show a header for the current file:

```
## Compressing [N]/[total]: [file-path]
```

### 4b: Pre-Analysis

Read the file, parse heading hierarchy, split into sections, flag structural issues. Show a brief section table (same format as `/markdown-compressor:compress` Step 3).

### 4c: Batched Compression

Process sections using the same batched approach as `/markdown-compressor:compress` Step 4, with auto-approve always active:

1. For each batch of up to 5 non-empty sections:
   - Dispatch all `section-compressor` agents in the batch in a single message (parallel Agent tool calls)
   - Agents are read-only (Read/Grep/Glob only) and receive section text in their prompt — they do not read or modify the target file. It is safe to dispatch all agents in a batch simultaneously.
   - Wait for all to return
2. If in lossy mode, dispatch all `compression-reviewer` agents in the batch in a single message (parallel Agent tool calls). Wait for all to return. Incorporate critical fixes automatically.
3. Show batch summary (one line per section):
   ```
   Section [N]/[total]: [heading] — ~X → ~Y tokens (-Z%)
   ```
4. Write all compressed sections in the batch to the file sequentially (top to bottom) using the Edit tool.
5. Re-read the file before processing the next batch.

### 4d: File Summary

After all sections in a file are processed, show:

```
[file-path]: ~X → ~Y tokens (-Z%), [A]/[B] sections modified
```

## Step 5: Aggregate Summary

After all files are processed:

```
## Compression Complete

| File | Original | Compressed | Reduction | Sections Modified |
|------|----------|------------|-----------|-------------------|
| ./CLAUDE.md | ~850 | ~520 | -39% | 9/12 |
| ./src/CLAUDE.md | ~320 | ~210 | -34% | 4/5 |
| ... | | | | |
| **Total** | **~X** | **~Y** | **-Z%** | **A/B** |
```

Inform the user: "All changes written. Use `git diff` to review or `git checkout .` to revert all."

## Mandatory Use of AskUserQuestion

Use `AskUserQuestion` at:
- Filename selection (if no argument)
- File list confirmation (compress all / exclude some)

All other processing is fully automatic. No per-section or per-file approval gates.

## Main Conversation Owns All User Interaction

Same rule as `/markdown-compressor:compress`: `AskUserQuestion` is called from this command only, never from subagents. Subagents compress and review — this command orchestrates.
