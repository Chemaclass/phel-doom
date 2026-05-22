#!/bin/bash
# PreToolUse hook: block edits to critical/generated files without explicit confirmation
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ -z "$FILE" ]] && exit 0

BASENAME=$(basename "$FILE")
if [[ "$BASENAME" == "composer.lock" ]] || \
   [[ "$BASENAME" == "phel-config.php" ]] || \
   [[ "$FILE" == */out/main.php ]] || \
   [[ "$FILE" == out/main.php ]] || \
   [[ "$FILE" == */.phel/cache/* ]] || \
   [[ "$FILE" == .phel/cache/* ]]; then
    echo "Protected file: $FILE — edit blocked. Ask user to confirm before retrying." >&2
    exit 2
fi
exit 0
