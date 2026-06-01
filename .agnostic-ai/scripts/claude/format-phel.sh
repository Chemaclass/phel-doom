#!/bin/bash
# PostToolUse hook: auto-format Phel files after Edit/Write
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ "$FILE" == *.phel ]]; then
    PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    cd "$PROJECT_DIR" 2>/dev/null
    vendor/bin/phel format "$FILE" >/dev/null 2>&1
fi
exit 0
