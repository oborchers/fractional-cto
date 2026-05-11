---
name: using-planning-tools
description: "This skill should be used when the user invokes /plan-delete or any other /plan-* command from the planning-tools plugin, asks how Claude Code's plan files work, asks where plans are stored, asks to clean up stale plan files, mentions ~/.claude/plans/, or asks how to reset/clear/inspect/archive plan-mode artifacts. Provides the index of planning-tools commands and the mechanics of Claude Code's plan-mode file storage."
version: 0.1.0
---

# Planning Tools

Claude Code's plan mode persists plans to disk at `~/.claude/plans/<slug>.md`. The slug is a random three-word adjective string (e.g., `moonlit-swimming-petal.md`) allocated at first plan creation in a session. That slug is **reused across re-plans and compactions within the session**. Across sessions, each session gets its own slug. The file persists across `/clear`, compactions, and session resumes, and accumulates content as plans evolve.

This plugin provides commands that operate on those plan files without relying on Claude Code internals — every command uses the `$CLAUDE_CODE_SESSION_ID` env var and the session transcript at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` as the source of truth for "which plan file belongs to this session."

## Commands

| Command | Triggers On |
|---------|-------------|
| `/plan-delete` | User asks to clear/reset/delete the current session's plan file, complains the plan file is "stale" or "polluted with old content," or wants a fresh slate before the next plan. Detects this session's slug from the transcript, deletes the file, recreates it empty, and re-reads it so the session is primed. Bootstraps with EnterPlanMode → no-op plan → ExitPlanMode if plan mode has never been entered. |

## How Plan File Detection Works

Claude Code stamps every transcript entry with a top-level `"slug"` field once plan mode is entered. That slug equals the plan filename (without `.md`). This is the authoritative source — used by every command in this plugin:

1. Read `$CLAUDE_CODE_SESSION_ID` from the environment (the current session's UUID).
2. Compute the transcript path: `$HOME/.claude/projects/<encoded-cwd>/$CLAUDE_CODE_SESSION_ID.jsonl`
   - The encoded CWD replaces both `/` and `.` with `-` (e.g., `/Users/o/Code.nosync/x` becomes `-Users-o-Code-nosync-x`).
3. Extract the slug: `grep -m1 -o '"slug":"[^"]*"' <transcript> | sed 's/"slug":"//; s/"$//'`
4. The plan file is `~/.claude/plans/<slug>.md`.

If the grep returns empty, the session has not entered plan mode yet — bootstrap with `EnterPlanMode` → minimal no-op plan → `ExitPlanMode`, then re-extract.

**Why not "most recently modified file in ~/.claude/plans/"?** Parallel sessions in other terminals/projects write to their own slugs concurrently. mtime is unreliable.

**Why not grep the transcript for `~/.claude/plans/<slug>.md` paths?** That matches any plan path mentioned in conversation (e.g., `ls` output), not just the session's true plan slug. The `"slug"` field is set by Claude Code itself and is unambiguous.

## Why This Matters

Plan files are external to Claude's context window and survive context compaction by design. After compaction Claude can lose awareness of the plan file's path unless explicitly re-read. A session with stale plan content in the slug file will append to or overwrite that content on the next plan-mode entry, leading to confused or merged plans. `/plan-delete` solves both: it removes accumulated cruft AND re-reads the now-empty file so subsequent plan operations have a clean canvas.

## Future Commands (Roadmap)

This plugin will grow. Planned additions:
- `/plan-master` — Promote the current plan to a permanent project-local file
- Additional `/plan-*` commands as workflows emerge

When adding new commands, follow the detection algorithm above (transcript-based, never mtime-based) and update this index.
