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
# it: `composer test` leaves every namespace cached, and a `php/new` probe then
# passes clean. `phel test` has no --no-cache and the cache key does not include
# the flag (phel-lang#3222), so this step needs a compile it controls.
#
# It used to get one by deleting the shared cache, which cost a full cold
# recompile every single run: 25.4s of a 41s gate, 62% of it, paid on every
# commit including the ones that changed one line of a doc. Instead it keeps its
# OWN cache directory (PHEL_CACHE_DIR), so only what actually changed since the
# last run recompiles - 11.2s instead of 25.4s - while a fresh clone and CI,
# which have no such directory, still compile everything.
#
# Two things make that safe:
#
#   1. The directory name carries a hash of composer.lock and phel-config.php.
#      A phel upgrade can deprecate a form that compiled clean yesterday, and an
#      optimisation-level change alters what is generated, so either one starts
#      a new cache rather than trusting the old one.
#   2. A run that FINDS something deletes the cache before exiting. Without
#      that, the offending file is now cached with its warning already emitted,
#      so the very next run is green with nothing fixed - a gate you can pass by
#      running it twice, which is worse than no gate. Failure costs the next run
#      a cold compile; that is the correct price.
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

# Toolchain fingerprint: composer.lock pins the compiler, phel-config.php sets
# the optimisation level. Either changing means yesterday's compile output is
# not evidence about today's.
key="$(cat composer.lock phel-config.php 2>/dev/null | md5 2>/dev/null || cat composer.lock phel-config.php 2>/dev/null | md5sum | cut -d' ' -f1)"
key="${key:0:12}"
cache="$root/.phel/cache-deprecations-$key"

# Never rm outside the project's own .phel/, whatever the key expands to.
case "$cache" in
  "$root"/.phel/cache-deprecations-?*) ;;
  *) echo "check-deprecations: refusing to use '$cache' (not under $root/.phel)"; exit 2 ;;
esac

# Drop caches from a previous toolchain so they do not accumulate.
for old in "$root"/.phel/cache-deprecations-*; do
  [ -d "$old" ] || continue
  [ "$old" = "$cache" ] && continue
  echo "check-deprecations: pruning stale cache $old"
  rm -rf "$old"
done

if [ -d "$cache" ]; then
  echo "check-deprecations: reusing compile cache $cache (only changed files recompile)"
else
  echo "check-deprecations: cold compile into $cache"
fi

log=$(mktemp "${TMPDIR:-/tmp}/phel-doom-deprecations.XXXXXX")
trap 'rm -f "$log"' EXIT

# Delete the cache so the next run recompiles from scratch. Called on every
# non-success path: a cached warning is emitted once and never again.
drop_cache() {
  [ -d "$cache" ] || return 0
  echo "check-deprecations: dropping compile cache $cache"
  rm -rf "$cache"
}

# Ctrl-C is a non-success path too, and the worst one: the run stops after some
# namespaces have compiled - emitting their warnings into a log nobody reads -
# and those are now cached. Without this, an interrupted run could leave the
# next one green with a live deprecation. Bash happens to reach the no-result
# branch below today, which drops the cache anyway; this makes it a decision
# rather than a signal-timing accident.
trap 'drop_cache; exit 130' INT TERM

PHEL_CACHE_DIR="$cache" PHEL_WARN_DEPRECATIONS=1 PHEL_DOOM_SILENT=1 vendor/bin/phel test >"$log" 2>&1
status=$?

if ! grep -qE '^Total: [0-9]+' "$log"; then
  echo "check-deprecations: the suite produced no result line - it did not run."
  tail -20 "$log"
  drop_cache
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
  # Overridable so the fixtures do not clobber a real failure log with a
  # stubbed one - which they did, and which makes the copy useless exactly
  # when someone reaches for it.
  failure_log="${PHEL_DOOM_CI_LOG:-/tmp/phel-doom-ci-failure.log}"
  echo "Full output: $log (copied to $failure_log)"
  cp "$log" "$failure_log" 2>/dev/null
  drop_cache
  exit "$status"
fi

if grep -inE 'deprecat' "$log"; then
  echo
  echo "DEPRECATION: see the lines above."
  echo "  - a superseded interop form: rewrite it (php/new -> (new \\Foo ...))."
  echo "  - 'loses precision': a float reached an int-inferred parameter and was"
  echo "    TRUNCATED, not rejected. Treat it as a wrong-answer bug, not a warning."
  echo
  echo "The compile cache has been dropped, so the next run recompiles and will"
  echo "report this again until it is fixed - running it twice cannot clear it."
  drop_cache
  exit 1
fi

echo "Deprecations OK: $(grep -oE '^Total: [0-9]+' "$log" | grep -oE '[0-9]+') tests, no compiler or float-truncation notices."
