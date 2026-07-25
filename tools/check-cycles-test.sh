#!/usr/bin/env bash
# Regression fixtures for tools/check-cycles.php.
#
# The cycle guard has been wrong twice, both times silently: once reporting a
# phantom cycle on a commented-out require (red CI on an acyclic graph), once
# dropping a whole namespace so a real cycle became invisible. Hand review did
# not catch either. Every fixture below is valid Phel that the guard once got
# wrong, plus positive controls so a guard that never fires cannot pass.
#
# Run: bash tools/check-cycles-test.sh   (wired into `composer check-cycles`)
set -uo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/check-cycles.php"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src"
cd "$WORK" || exit 2
cp "$GUARD" ./check-cycles.php

pass=0
fail=0

# expect: "cycle" = must exit non-zero, "clean" = must exit zero
check() {
  local name="$1" expect="$2"
  local out rc
  out="$(php check-cycles.php 2>&1)"
  rc=$?
  if { [ "$expect" = "cycle" ] && [ "$rc" -ne 0 ]; } || { [ "$expect" = "clean" ] && [ "$rc" -eq 0 ]; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL  $name (expected $expect, exit $rc)"
    echo "      $out"
  fi
  rm -f src/*.phel
}

# --- fail-open cases: a real cycle the guard must not miss -------------------

printf '(ns phel-doom.a\n  (:require [phel-doom.b :as b]))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
check "vector require [ns :as x] hiding a cycle" cycle

printf '(ns phel-doom.a\n  (:require phel-doom.c phel-doom.b))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
printf '(ns phel-doom.c)\n' > src/c.phel
check "multi-entry require clause hiding a cycle" cycle

printf '(ns phel-doom.a\n  (:require #_phel-doom.evil phel-doom.b))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
check "#_ discard before the real require" cycle

printf '(ns\n  phel-doom.a\n  (:require phel-doom.b))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
check "newline after (ns" cycle

printf '(ns phel-doom.a\n  (:require phel-doom.b))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
check "positive control: plain 2-node cycle" cycle

# --- fail-closed cases: acyclic code the guard must not flag ----------------

printf '(ns phel-doom.a\n  ;; (:require phel-doom.b)\n  (:require phel-doom.c))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
printf '(ns phel-doom.c)\n' > src/c.phel
check "; commented-out require is not an edge" clean

printf '(ns phel-doom.a\n  # (:require phel-doom.b)\n  (:require phel-doom.c))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
printf '(ns phel-doom.c)\n' > src/c.phel
check "bare # line comment is not an edge" clean

printf '(ns phel-doom.a\n  #_#_(:require phel-doom.b) (:require phel-doom.b)\n  (:require phel-doom.c))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
printf '(ns phel-doom.c)\n' > src/c.phel
check "stacked #_#_ discards two forms" clean

printf '#| (ns phel-doom.fake (:require phel-doom.evil)) |#\n(ns phel-doom.a\n  (:require phel-doom.b))\n' > src/a.phel
printf '(ns phel-doom.b)\n' > src/b.phel
check "fake ns inside a #| |# block comment" clean

printf '(ns phel-doom.a\n  "Docstring naming phel-doom.b and (:require phel-doom.b)."\n  (:require phel-doom.c))\n' > src/a.phel
printf '(ns phel-doom.b\n  (:require phel-doom.a))\n' > src/b.phel
printf '(ns phel-doom.c)\n' > src/c.phel
check "namespace named only in a docstring is not an edge" clean

# --- structural failure must be loud, not a dropped node --------------------

printf '(this-is-not-an-ns-form)\n' > src/a.phel
out="$(php check-cycles.php 2>&1)"; rc=$?
if [ "$rc" -eq 2 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL  unparseable ns form must exit 2 (got $rc): $out"
fi
rm -f src/*.phel

echo "check-cycles fixtures: $pass passed, $fail failed."
[ "$fail" -eq 0 ] || exit 1
