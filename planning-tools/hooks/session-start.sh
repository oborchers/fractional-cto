#!/usr/bin/env bash
# SessionStart hook for planning-tools plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

session_context="<IMPORTANT>\nYou have the planning-tools plugin installed.\n\nThis plugin manages Claude Code's plan-mode artifacts that live at ~/.claude/plans/<slug>.md. Each session reuses its allocated slug across re-plans and compactions, so the file accumulates content unless explicitly cleared.\n\nAvailable commands:\n- /plan-delete — Clear the current session's plan file: detect via \$CLAUDE_CODE_SESSION_ID + transcript grep, delete, recreate empty, re-read so the session is primed for the next plan. If the session has not entered plan mode yet, bootstrap with a no-op plan (EnterPlanMode → minimal placeholder → ExitPlanMode) before cleaning.\n\nFor methodology and detection details, see the using-planning-tools skill.\n</IMPORTANT>"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${session_context}"
  }
}
EOF

exit 0
