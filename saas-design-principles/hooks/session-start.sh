#!/usr/bin/env bash
# SessionStart hook for saas-design-principles plugin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read the using-saas-principles skill content
using_skill_content=$(cat "${PLUGIN_ROOT}/skills/using-saas-principles/SKILL.md" 2>&1 || echo "Error reading using-saas-principles skill")

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

using_skill_escaped=$(escape_for_json "$using_skill_content")
session_context="<IMPORTANT>\nYou have the saas-design-principles plugin installed.\n\n**Below is the skill index. For individual principles, use the 'Skill' tool:**\n\n${using_skill_escaped}\n</IMPORTANT>"

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
