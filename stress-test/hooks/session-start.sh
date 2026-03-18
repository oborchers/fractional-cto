#!/usr/bin/env bash
# SessionStart hook for stress-test plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read the stress-test-methodology skill content
skill_content=$(cat "${PLUGIN_ROOT}/skills/stress-test-methodology/SKILL.md" 2>&1 || echo "Error reading stress-test-methodology skill")

# Escape string for JSON embedding
escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

skill_escaped=$(escape_for_json "$skill_content")
session_context="<IMPORTANT>\nYou have the stress-test plugin installed.\n\nWhen users want to review a plan for gaps, challenge assumptions, stress-test a planning document, or ask 'is my plan sound' or 'what could go wrong', invoke the /stress-test command.\n\n**Below is the methodology skill. For details, use the 'Skill' tool:**\n\n${skill_escaped}\n</IMPORTANT>"

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
