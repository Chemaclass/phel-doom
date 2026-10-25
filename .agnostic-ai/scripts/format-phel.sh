#!/bin/bash
# after-edit hook: format the .phel files the agent edited
INPUT=$(cat)
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || exit 0
command -v agnostic-ai >/dev/null 2>&1 || exit 0

printf '%s' "$INPUT" | agnostic-ai hook paths 2>/dev/null | grep '\.phel$' | while IFS= read -r f; do
    vendor/bin/phel format "$f" >/dev/null 2>&1
done
exit 0
