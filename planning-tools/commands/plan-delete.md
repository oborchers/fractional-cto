---
description: "Clear the current session's plan file in ~/.claude/plans/ — delete, recreate empty, re-read to prime the next plan"
---

Clear the current session's Claude Code plan file. Plans accumulate in `~/.claude/plans/<slug>.md` as plan mode is re-entered within a session — this command resets to a clean slate.

Follow these steps exactly. Do **not** prompt the user for confirmation; the explicit `/planning-tools:plan-delete` invocation is the confirmation.

## Step 1: Detect the current session's plan slug

Claude Code stamps every transcript entry with a top-level `"slug"` field once plan mode is entered. That slug equals the plan filename (without `.md`). This is the authoritative signal — far more reliable than path-grepping or file mtime.

Run this bash one-liner:

```bash
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$SESSION_ID" ]; then
  echo "ERROR: CLAUDE_CODE_SESSION_ID not set"; exit 1
fi
# Session IDs are globally unique UUIDs; find the transcript wherever it lives
# (more robust than computing the encoded-CWD path, which is fragile for paths with spaces/Unicode).
TRANSCRIPT="$(find "$HOME/.claude/projects" -name "${SESSION_ID}.jsonl" -type f 2>/dev/null | head -1)"
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo "NO_TRANSCRIPT"; exit 0
fi
SLUG="$(grep -m1 -o '"slug":"[^"]*"' "$TRANSCRIPT" 2>/dev/null | sed 's/"slug":"//; s/"$//')"
if [ -z "$SLUG" ]; then
  echo "NO_PLAN_FOUND"
else
  # Defense in depth: slugs are random adjective-style strings like "moonlit-swimming-petal".
  # Reject anything that could escape ~/.claude/plans/ (slashes, dots, control chars, spaces).
  case "$SLUG" in
    *[!a-z0-9-]*|""|*--*|-*|*-)
      echo "ERROR: malformed slug rejected: '$SLUG'"; exit 1 ;;
  esac
  PLAN_PATH="$HOME/.claude/plans/${SLUG}.md"
  echo "SLUG=$SLUG"
  echo "PLAN_PATH=$PLAN_PATH"
  ls -la "$PLAN_PATH" 2>/dev/null || echo "(file no longer exists on disk)"
fi
```

Interpret the output:
- `SLUG=<x>` and `PLAN_PATH=<path>` → go to Step 3
- `NO_TRANSCRIPT` or `NO_PLAN_FOUND` → go to Step 2 (bootstrap)

## Step 2: Bootstrap a plan file (only if Step 1 returned NO_PLAN_FOUND / NO_TRANSCRIPT)

Plan mode has not been entered yet this session, so no slug has been allocated. Bootstrap one with a no-op plan:

1. Call the `EnterPlanMode` tool.
2. While in plan mode, call `ExitPlanMode` with this exact placeholder content:

   ```
   # Plan placeholder

   No work planned. This plan was created by /planning-tools:plan-delete to allocate a session slug for cleanup. Reject this plan immediately — do not approve.
   ```

3. When Claude Code prompts the user to approve the plan, the placeholder text is self-explanatory. Either rejection or accidental approval is fine — the file will be deleted in Step 3 either way.

4. After exiting plan mode, **re-run the detection bash from Step 1**. The transcript now has the newly allocated slug stamped on it. Capture `SLUG` and `PLAN_PATH`.

If the slug is still empty after the bootstrap, report the failure to the user and stop — the EnterPlanMode/ExitPlanMode cycle did not allocate a slug, which suggests a Claude Code version or sandbox issue worth investigating manually.

## Step 3: Delete, touch, re-read

With `PLAN_PATH` known, run this bash sequence. The guard re-asserts the path prefix before deletion as a second safety net (the slug was already validated in Step 1, but this is cheap insurance):

```bash
case "$PLAN_PATH" in
  "$HOME/.claude/plans/"*.md) : ;;  # ok
  *) echo "ERROR: refusing to delete unexpected path: $PLAN_PATH"; exit 1 ;;
esac
rm -f "$PLAN_PATH"
touch "$PLAN_PATH"
echo "Cleared: $PLAN_PATH"
ls -la "$PLAN_PATH"
```

Then use the `Read` tool to read `$PLAN_PATH`. This places the now-empty plan file into your context so the next plan-mode entry writes into a known-clean state. (An empty file will trigger Read's empty-content warning — that is expected and confirms success.)

## Step 4: Report

Output one concise line to the user, e.g.:

```
Cleared ~/.claude/plans/moonlit-swimming-petal.md (was 9.3 KB). Plan file is empty and re-read into context. Next plan-mode entry will write into a clean slate.
```

If the bootstrap path was taken, prefix with: `Bootstrapped plan slug via no-op plan, then cleared.`

## Notes on Detection Reliability

- **The `"slug"` field in the transcript JSONL is the authoritative source.** Claude Code stamps it on every entry once plan mode is entered, and it equals the plan filename without `.md`. Use it.
- **`$CLAUDE_CODE_SESSION_ID` is set by Claude Code in every shell it spawns.** If unset, the user is likely running this outside a Claude Code session — abort.
- **Transcript location: `find ~/.claude/projects -name "${SESSION_ID}.jsonl"`** is more robust than computing the encoded-CWD path (which is fragile for CWDs containing spaces or non-ASCII characters). Session IDs are globally unique UUIDs, so the find returns exactly one file.
- **Never use "most recently modified file in ~/.claude/plans/"** as a fallback. Parallel sessions in other terminals/projects write to their own slugs concurrently, so mtime is unreliable.
- **Never grep the transcript for `~/.claude/plans/<slug>.md` paths.** That matches any plan path mentioned in conversation (e.g., `ls` output), not just the session's true plan slug.
- **Always validate the slug format before constructing the path.** The validation in Step 1 plus the path-prefix guard in Step 3 ensures the command can never delete outside `~/.claude/plans/`.

## Mandatory Use of AskUserQuestion

This command intentionally has **no** decision points — the explicit `/planning-tools:plan-delete` invocation is the only consent needed. If a future variant adds optional behavior (e.g., archive-before-delete), use `AskUserQuestion` per fractional-cto convention. This command runs in the main conversation; no subagents are needed.
