#!/usr/bin/env bash
# Regression fixtures for tools/check-unused.php.
#
# A guard that reports dead code has two ways to be useless, and both are
# quiet: flag something that IS used (so the next contributor deletes a live
# definition, or learns to ignore the guard), or miss something dead (so it
# never earns its place in the gate). Every case below is Phel this guard has
# to get right, with positive controls so a guard that never fires cannot pass.
#
# Run: bash tools/check-unused-test.sh   (wired into `composer check-unused`)
set -uo pipefail

TOOLS="$(cd "$(dirname "$0")" && pwd)"
GUARD="$TOOLS/check-unused.php"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/phel-doom-unused.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/tests" "$WORK/tools" "$WORK/lib"
cd "$WORK" || exit 2
cp "$GUARD" ./check-unused.php
cp "$TOOLS/lib/phel-source.php" ./lib/phel-source.php

pass=0
fail=0

# expect: "dead" = must exit non-zero, "clean" = must exit zero
check() {
  local name="$1" expect="$2"
  local out rc
  out="$(php check-unused.php 2>&1)"
  rc=$?
  if { [ "$expect" = "dead" ] && [ "$rc" -ne 0 ]; } || { [ "$expect" = "clean" ] && [ "$rc" -eq 0 ]; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL  $name (expected $expect, exit $rc)"
    echo "      ${out//$'\n'/$'\n'      }"
  fi
  rm -f src/*.phel tests/*.phel tools/*.phel
}

# --- fail-open cases: dead code the guard must not miss ----------------------

cat > src/a.phel <<'EOF'
(ns app.a)
(def used 1)
(def orphan 2)
(defn entry [] used)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry)
EOF
check "a def nothing references" dead

# The real case: a constant a refactor stopped using, whose docstring still
# describes the behaviour. Prose must never count as a reference.
cat > src/a.phel <<'EOF'
(ns app.a)
(def tex-offset
  "Half a tile of shift, applied to a secret wall's column.
   See tex-offset for why it is 32 and not 64."
  32)
(defn shift [tsz] (php/intdiv tsz 2))
(defn entry [n] (shift n))
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry 64)
EOF
check "a def mentioned only in its own docstring" dead

cat > src/a.phel <<'EOF'
(ns app.a)
(def orphan 1)
;; orphan is kept around for later
#_(orphan)
(defn entry [] 1)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry)
EOF
check "a def used only from a comment and a #_ discard" dead

# --- fail-shut cases: live code the guard must not flag ----------------------

cat > src/a.phel <<'EOF'
(ns app.a)
(def shared 1)
EOF
cat > src/b.phel <<'EOF'
(ns app.b (:require app.a :as a))
(defn entry [] a/shared)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.b :refer [entry]))
(entry)
EOF
check "a def referenced through a namespace alias" clean
rm -f src/b.phel

cat > src/a.phel <<'EOF'
(ns app.a)
(defn alive? [x] x)
(defn set-thing! [x] x)
(defn ->rec [x] x)
(defn entry [x] (if (alive? x) (set-thing! (->rec x)) x))
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry 1)
EOF
check "names carrying ? ! and -> in them" clean

cat > src/a.phel <<'EOF'
(ns app.a)
(def grid [1 2 3])
(defn entry [] 1)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [grid entry]))
(is (= 3 (count grid)))
(entry)
EOF
check "a fixture referenced only from tests" clean

cat > src/a.phel <<'EOF'
(ns app.a)
(defmacro when-lit [x & body] `(if ~x (do ~@body) nil))
(defstruct point [x y])
(defn entry [] (when-lit true (point 1 2)))
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry)
EOF
check "a macro and a struct used from the same file" clean

# A prefix must not count: `use` is not a reference to `used`, and the guard
# must not let a longer neighbour hide a dead short name.
cat > src/a.phel <<'EOF'
(ns app.a)
(def use 1)
(def used-up 2)
(defn entry [] used-up)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry)
EOF
check "a name that is a prefix of a live one" dead

cat > src/a.phel <<'EOF'
(ns app.a)
(def cap 10)
(def cap-hard 20)
(defn entry [] (php/min cap cap-hard))
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry)
EOF
check "two names where one is a prefix of the other, both used" clean

# A tool script is a legitimate consumer: the bake tools call into src/.
cat > src/a.phel <<'EOF'
(ns app.a)
(defn bake-table [] 1)
(defn entry [] 1)
EOF
cat > tools/bake.phel <<'EOF'
(ns tools.bake (:require app.a :refer [bake-table]))
(bake-table)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry)
EOF
check "a def referenced only from tools/" clean

# `defstruct point` also defines `point?`, so a struct reached only through
# its predicate is live - the exact false positive these fixtures exist to
# stop, since the fix for it is to delete a struct that is in use.
cat > src/a.phel <<'EOF'
(ns app.a)
(defstruct point [x y])
(defn entry [v] (point? v))
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry 1)
EOF
check "a struct used only through its generated predicate" clean

# ^:pure and ^:private sit between the form and the name. Reading the meta as
# the name and giving up hid 30 real definitions, and the count printed at the
# end was quietly 30 short.
cat > src/a.phel <<'EOF'
(ns app.a)
(defn ^:pure orphan [x] x)
(defn entry [] 1)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry)
EOF
check "a metadata-tagged def nothing references" dead

cat > src/a.phel <<'EOF'
(ns app.a)
(defn ^:pure twice [x] (php/* 2 x))
(defn entry [x] (twice x))
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry 2)
EOF
check "a metadata-tagged def that is used" clean

# A facade re-export defines the name a second time. Keeping only one site let
# the two mask each other: each defining line read as a use of the other, so
# neither could ever be flagged.
cat > src/a.phel <<'EOF'
(ns app.a)
(defn deep-thing [] 1)
EOF
cat > src/facade.phel <<'EOF'
(ns app.facade (:require app.a :as a))
(def deep-thing a/deep-thing)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a))
EOF
check "a name defined twice, used by neither" dead
rm -f src/facade.phel

cat > src/a.phel <<'EOF'
(ns app.a)
(defn deep-thing [] 1)
EOF
cat > src/facade.phel <<'EOF'
(ns app.facade (:require app.a :as a))
(def deep-thing a/deep-thing)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.facade :refer [deep-thing]))
(deep-thing)
EOF
check "a name defined twice and actually used" clean
rm -f src/facade.phel

# Privates count. `composer lint` passes clean on an unused `def-` AND an
# unused `defn-` (checked directly), so if this guard skips them nothing at
# all covers them - which is how #516 left a dead `bfs-steps` behind.
cat > src/a.phel <<'EOF'
(ns app.a)
(def- orphan-const 1)
(defn- orphan-helper [x] x)
(defn entry [] 1)
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry)
EOF
check "an unused private def and defn" dead

cat > src/a.phel <<'EOF'
(ns app.a)
(def- step 2)
(defn- twice [x] (php/* step x))
(defn entry [x] (twice x))
EOF
cat > tests/a-test.phel <<'EOF'
(ns app.a-test (:require app.a :refer [entry]))
(entry 3)
EOF
check "privates used only inside their own file" clean

echo "check-unused fixtures: $pass passed, $fail failed."
[ "$fail" -eq 0 ] || exit 1
