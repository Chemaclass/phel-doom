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
# Class 1 is raised while a namespace COMPILES, so a warm compile cache hides
# it: `composer test` right before this step (as `composer ci` runs it) leaves
# every namespace cached, and a `php/new` probe then passes clean. The cache
# is cleared first so the whole tree recompiles under the flag. `phel test`
# has no --no-cache, and the cache key does not include the flag.
#
# This is also the gate's ONLY suite run. `composer ci` used to run
# `composer test` first and then this: the same 3800 tests twice, 12s warm
# plus 28s cold, for 40s of a 50s gate. The cold run is a superset - it
# compiles everything from scratch AND runs every test - so the warm one
# was pure duplication. `composer test` on its own is untouched and stays
# the fast way to run tests while working.
#
# Fail-closed: an empty run (no tests discovered) is a failure, not a pass.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 2
cache="$root/.phel/cache"   # phel-config default `cache-dir`; `vendor/bin/phel config` prints it
case "$cache" in
  "$root"/.phel/*) ;;
  *) echo "check-deprecations: refusing to clear '$cache' (not under $root/.phel)"; exit 2 ;;
esac
echo "check-deprecations: clearing compile cache $cache"
rm -rf "$cache"

log=$(mktemp "${TMPDIR:-/tmp}/phel-doom-deprecations.XXXXXX")
trap 'rm -f "$log"' EXIT

PHEL_WARN_DEPRECATIONS=1 PHEL_DOOM_SILENT=1 vendor/bin/phel test >"$log" 2>&1
status=$?

if ! grep -qE '^Total: [0-9]+' "$log"; then
  echo "check-deprecations: the suite produced no result line - it did not run."
  tail -20 "$log"
  exit 2
fi

if [ "$status" -ne 0 ]; then
  # This is the gate's only suite run, so a plain test failure lands here.
  # Print the failures themselves, not just the tail, or the developer has
  # to re-run the suite by hand to find out what broke.
  echo "check-deprecations: the suite failed."
  echo
  grep -E "^(FAIL|Error|Failed asserting|Total|Passed|Failed)" "$log" | head -40
  echo
  echo "Full output: $log (copied to /tmp/phel-doom-ci-failure.log)"
  cp "$log" /tmp/phel-doom-ci-failure.log 2>/dev/null
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
