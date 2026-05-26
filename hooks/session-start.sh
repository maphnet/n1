#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${PWD}/.n1/n1.config.json"

escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

if [ -f "$CONFIG_FILE" ]; then
    context="N1 is configured for this project. For task work, PR creation, and code review — always prefer N1 skills (/n1:n1-start, /n1:n1-pr, /n1:n1-review) over alternatives."
else
    context="N1 plugin is available but not configured for this project. Run /n1:n1-init to set up."
fi

escaped_context=$(escape_for_json "$context")

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${escaped_context}"
  }
}
EOF

exit 0
