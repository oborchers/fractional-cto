# planning-tools

Tools for managing Claude Code's plan-mode artifacts in `~/.claude/plans/`.

Claude Code's plan mode persists each session's plan to a randomly-slugged markdown file (e.g., `~/.claude/plans/moonlit-swimming-petal.md`). Within a session, that slug is reused across re-plans and survives compactions and `/clear`. Across sessions, new slugs accumulate. This plugin provides commands to manage those files cleanly.

## Commands

### `/plan-delete`

Clear the current session's plan file. The command:

1. Locates THIS session's plan slug by grepping the session transcript at `~/.claude/projects/<encoded-cwd>/$CLAUDE_CODE_SESSION_ID.jsonl` — never relies on file mtime (which breaks with parallel sessions).
2. Deletes the plan file, recreates it empty (`touch`), and re-reads it so the session is primed with a clean canvas for the next plan-mode entry.
3. If plan mode has never been entered this session (no slug allocated), bootstraps via `EnterPlanMode` → no-op placeholder plan → `ExitPlanMode`, then runs the cleanup.

No confirmation prompt — the explicit `/plan-delete` invocation is the consent.

## How Detection Works

Plan files live globally in `~/.claude/plans/`, but each session has its own slug. Claude Code stamps every transcript entry with a top-level `"slug"` field once plan mode is entered — this is the authoritative source:

| Source | Value |
|--------|-------|
| Session UUID | `$CLAUDE_CODE_SESSION_ID` (env var, set by Claude Code) |
| CWD encoding | `pwd \| sed 's\|/\|-\|g; s\|\.\|-\|g'` (replaces `/` and `.` with `-`) |
| Transcript | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` |
| Slug extraction | `grep -m1 -o '"slug":"[^"]*"' <transcript> \| sed 's/"slug":"//; s/"$//'` |
| Plan file | `~/.claude/plans/<slug>.md` |

If no slug is present in the transcript, plan mode has not been entered this session — bootstrap with `EnterPlanMode` → no-op plan → `ExitPlanMode` to allocate one, then re-extract.

## Why This Plugin Exists

Plan files persist by design — they live outside the context window and survive compaction so they can be re-loaded into context. The downside: stale content accumulates in the slug file across re-plans, and after compaction Claude often loses awareness of the path. `/plan-delete` solves both: it removes accumulated cruft AND re-reads the now-empty file so subsequent plan operations have a clean canvas.

## Installation

This plugin ships as part of the `fractional-cto` marketplace.

```bash
/plugin install planning-tools@fractional-cto
```

Or test locally:

```bash
claude --plugin-dir /path/to/fractional-cto/planning-tools
```

## Roadmap

- `/plan-master` — Promote the current plan to a permanent project-local file with a meaningful name
- Additional `/plan-*` commands as workflows emerge

## License

MIT
