#!/usr/bin/env bash
# SessionStart hook for markdown-compressor plugin
# NOTE: Session context is hardcoded below. If SKILL.md scope changes, update this string to match.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

session_context="<IMPORTANT>\nYou have the markdown-compressor plugin installed.\n\nWhen users want to compress markdown files, shrink LLM instructions, optimize agent prompts, reduce token usage in documentation, or minimize CLAUDE.md / ARCHITECTURE.md file sizes, invoke the markdown-compression skill. Use the /compress command for guided section-by-section compression.\n\nTwo modes available:\n- Lossless: structural optimization (whitespace, formatting, redundancy) — zero semantic change\n- Lossy: semantic compression (rewrite for density, remove filler, consolidate) — preserves critical information\n\nThe /compress command reads the file, pre-analyzes section structure, then iterates section-by-section with compressor and reviewer agents, presenting diffs for user approval.\n</IMPORTANT>"

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
