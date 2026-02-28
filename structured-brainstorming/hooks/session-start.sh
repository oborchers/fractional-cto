#!/usr/bin/env bash
# SessionStart hook for structured-brainstorming plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

session_context="<IMPORTANT>\nYou have the structured-brainstorming plugin installed.\n\nWhen users are stuck, exploring a problem space, need to think through options, or ask 'how should I approach this', invoke the structured-brainstorming skill. Use the /brainstorm command for guided sessions.\n\nAvailable methods: First Principles, Inversion/Pre-Mortem, Constraint Manipulation, Perspective Forcing, Analogy Search, MECE Decomposition, Assumption Surfacing, Diverge-then-Converge.\n\nFor deep exploration, spawn parallel brainstorm-explorer subagents.\n</IMPORTANT>"

cat <<EOF
{
  "additional_context": "${session_context}",
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${session_context}"
  }
}
EOF

exit 0
