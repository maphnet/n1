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

# Extract a nested JSON string value using a two-level dotted path.
# Usage: json_val '.tracker.mcp' file.json
# For paths like .tracker.mcp, extracts the "mcp" value within the "tracker" block.
json_val() {
    local path="$1" file="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -r "${path} // empty" "$file" 2>/dev/null || true
        return
    fi
    # Fallback: section-aware grep.
    # Split path into section and key (e.g. .tracker.mcp -> tracker, mcp)
    local stripped="${path#.}"
    local section="${stripped%%.*}"
    local key="${stripped#*.}"
    if [ "$section" = "$key" ]; then
        # Single-level path — search whole file
        grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null \
            | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/' || true
    else
        # Two-level path — extract section first, then search within it
        awk -v sec="\"${section}\"" '
            $0 ~ sec { found=1; depth=0 }
            found && /{/ { depth++ }
            found && /}/ { depth--; if(depth<=0) { found=0 } }
            found { print }
        ' "$file" 2>/dev/null \
            | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
            | head -1 | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/' || true
    fi
}

# Extract the operations map as key=value pairs.
# Usage: json_ops '.tracker.operations' file.json
json_ops() {
    local path="$1" file="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -r "${path} // {} | to_entries | map(\"\(.key)=\(.value)\") | join(\", \")" "$file" 2>/dev/null || true
        return
    fi
    # Fallback: extract the operations block within the parent section.
    local stripped="${path#.}"
    local section="${stripped%%.*}"
    local opkey="${stripped#*.}"
    # First extract the parent section, then the operations sub-block
    awk -v sec="\"${section}\"" '
        $0 ~ sec { found=1; depth=0 }
        found && /{/ { depth++ }
        found && /}/ { depth--; if(depth<=0) { found=0 } }
        found { print }
    ' "$file" 2>/dev/null \
        | awk -v ops="\"${opkey}\"" '
            $0 ~ ops { found=1; depth=0 }
            found && /{/ { depth++ }
            found && /}/ { depth--; if(depth<=0) { print; found=0; next } }
            found { print }
        ' 2>/dev/null \
        | grep -o '"[a-zA-Z_]*"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | grep -v "\"${opkey}\"" \
        | sed 's/"\([^"]*\)"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1=\2/' \
        | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g' || true
}

if [ ! -f "$CONFIG_FILE" ]; then
    context="N1 plugin is available but not configured for this project. Run /n1:n1-init to set up."
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
fi

context="N1 is configured for this project. For task work, PR creation, and code review — always prefer N1 skills (/n1:n1-start, /n1:n1-pr, /n1:n1-review, /n1:n1-ci) over alternatives."

tracker_mcp=$(json_val '.tracker.mcp' "$CONFIG_FILE")
tracker_type=$(json_val '.tracker.type' "$CONFIG_FILE")
tracker_ops=$(json_ops '.tracker.operations' "$CONFIG_FILE")
error_mcp=$(json_val '.errorTracking.mcp' "$CONFIG_FILE")
error_ops=$(json_ops '.errorTracking.operations' "$CONFIG_FILE")

if [ -n "$tracker_mcp" ]; then
    context="${context}

TRACKER ROUTING (from .n1/n1.config.json — authoritative, do not override):
- Type: ${tracker_type}
- MCP server: ${tracker_mcp}
- All tracker MCP tool calls MUST use prefix: mcp__${tracker_mcp}__
- NEVER use any other MCP server for tracker operations, even if other tracker-like servers are visible in the tool list
- Operations: ${tracker_ops}"
fi

if [ -n "$error_mcp" ]; then
    context="${context}

ERROR TRACKING ROUTING (from .n1/n1.config.json — authoritative, do not override):
- MCP server: ${error_mcp}
- All error tracking MCP tool calls MUST use prefix: mcp__${error_mcp}__
- NEVER use any other MCP server for error tracking operations
- Operations: ${error_ops}"
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
