#!/usr/bin/env bash
set -eu

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
paths=$(agnostic-ai hook paths --action)
while IFS= read -r change; do
  path=${change#*	}
  case "$path" in
    src/core/*|src/glue/*)
      bash tools/check-layers.sh >&2 || exit 2
      exit 0
      ;;
  esac
done <<< "$paths"
