#!/usr/bin/env bash
# Enforce the io/ -> glue/ -> core/ dependency direction (docs/architecture.md,
# .claude/rules/io-boundaries.md): core/ must not require io/ or glue/, and
# glue/ must not require io/. Realizes the "enforceable via (:require ...)
# inspection" invariant that was previously reviewer-only.
set -uo pipefail

fail=0

if grep -rnE 'phel-doom\.(io|glue)' src/core/; then
  echo "LAYERING VIOLATION: src/core/ must not require io/ or glue/ (see above)."
  fail=1
fi

if grep -rnE 'phel-doom\.io' src/glue/; then
  echo "LAYERING VIOLATION: src/glue/ must not require io/ (see above)."
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "Layering OK: io/ -> glue/ -> core/ dependency direction holds."
fi

exit "$fail"
