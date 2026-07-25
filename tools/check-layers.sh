#!/usr/bin/env bash
# Enforce the io/ -> glue/ -> core/ dependency direction (docs/architecture.md,
# .claude/rules/io-boundaries.md): the pure layers never reference a layer above
# them - core/ references only core/, glue/ only glue//core/, and neither the
# io/ nor the orchestration (commands/, demo/) layers. Greps whole .phel bodies
# (not just :require) so qualified refs + :as aliases are caught too; fail-closed.
set -uo pipefail

# A missing/renamed dir would make grep exit non-zero, which the `if`s below read
# as "no violation" - silently disarming the guard. Fail loud on a restructure.
for d in src/core src/glue src/demo; do
  [ -d "$d" ] || { echo "check-layers: expected directory $d not found (restructure?)"; exit 2; }
done

fail=0

if grep -rnE --include='*.phel' 'phel-doom\.(io|glue|commands|demo)' src/core/; then
  echo "LAYERING VIOLATION: src/core/ must reference only core/ (see above)."
  fail=1
fi

if grep -rnE --include='*.phel' 'phel-doom\.(io|commands|demo)' src/glue/; then
  echo "LAYERING VIOLATION: src/glue/ must not reference io/ or the orchestration layer (see above)."
  fail=1
fi

# io/ may use glue/ + core/ but must not reach UP into the orchestration layer.
# Require-scoped rather than whole-body like the checks above: src/io/sound.phel
# legitimately names `phel run phel-doom.main play` inside a docstring, and a
# body-wide grep would read that as an edge.
if grep -rnE --include='*.phel' '\(:require[[:space:]]+phel-doom\.(commands|main)' src/io/; then
  echo "LAYERING VIOLATION: src/io/ must not require commands/ or main (see above)."
  fail=1
fi

# demo/ is pure phase transforms over core/ (commands/demo.phel drives it), so it
# sits with glue/: it may reference core/ + glue/, never io/ or commands/.
if grep -rnE --include='*.phel' 'phel-doom\.(io|commands)' src/demo/; then
  echo "LAYERING VIOLATION: src/demo/ must not reference io/ or commands/ (see above)."
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "Layering OK: io/ -> glue/ -> core/ dependency direction holds."
fi

exit "$fail"
