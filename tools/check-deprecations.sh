#!/usr/bin/env bash
# Run the unit suite with every deprecation channel ON and fail if any fires.
#
# Two classes, both silent without this gate:
#
#   1. Compiler deprecations (phel's own, opt-in via PHEL_WARN_DEPRECATIONS):
#      `php/new`, `php/->`, `php/::`, `set-var`, `\` namespace separators.
#      Source that still spells the old form keeps compiling until the removal
#      release drops it.
#   2. PHP "Implicit conversion from float X to int loses precision". phel 0.50
#      infers a parameter's type from its body, so comparing a parameter to an
#      INT literal emits `int $p` - and a fractional caller is then truncated at
#      the signature with the wrong answer, no error, no failing test unless one
#      happens to assert that exact value. This is how `controls/sign` started
#      returning 0.0 for every sub-cell offset. See .claude/rules/phel.md
#      "Type inference traps".
#
# Fail-closed: an empty run (no tests discovered) is a failure, not a pass.
set -uo pipefail

log=$(mktemp -t phel-doom-deprecations)
trap 'rm -f "$log"' EXIT

PHEL_WARN_DEPRECATIONS=1 PHEL_DOOM_SILENT=1 vendor/bin/phel test >"$log" 2>&1
status=$?

if ! grep -qE '^Total: [0-9]+' "$log"; then
  echo "check-deprecations: the suite produced no result line - it did not run."
  tail -20 "$log"
  exit 2
fi

if [ "$status" -ne 0 ]; then
  echo "check-deprecations: the suite itself failed; fix that first."
  tail -20 "$log"
  exit "$status"
fi

if grep -inE 'deprecat' "$log"; then
  echo
  echo "DEPRECATION: see the lines above."
  echo "  - a superseded interop form: rewrite it (php/new -> (new \\Foo ...))."
  echo "  - 'loses precision': a float reached an int-inferred parameter and was"
  echo "    TRUNCATED, not rejected. Treat it as a wrong-answer bug, not a warning."
  exit 1
fi

echo "Deprecations OK: $(grep -oE '^Total: [0-9]+' "$log" | grep -oE '[0-9]+') tests, no compiler or float-truncation notices."
