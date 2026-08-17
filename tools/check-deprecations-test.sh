#!/usr/bin/env bash
# Regression fixtures for tools/check-deprecations.sh.
#
# This was the last guard without any, and it is the one whose failure mode is
# worst: it keeps a compile cache between runs, so every bug in its cache
# handling is a fail-OPEN - the suite passes while a deprecation sits in the
# tree. The behaviours below are what make reusing that cache safe, and each is
# a thing the script must do rather than a thing it happens to do:
#
#   a clean run KEEPS the cache          (the whole point: 11s instead of 25s)
#   a run that finds a deprecation DROPS it   (else `run it twice` turns green)
#   a run that produces no result DROPS it    (a crash mid-compile caches half)
#   an interrupted run DROPS it               (Ctrl-C caches half, silently)
#   a toolchain change starts a NEW cache     (an upgrade can deprecate old code)
#   stale caches are pruned                   (one per lockfile, forever, else)
#
# `phel test` is stubbed: these are tests of the cache logic, not of the
# compiler, and a real compile would put a 25-second suite inside a fixture.
# The stub's mode comes from FAKE_MODE.
#
# Run: bash tools/check-deprecations-test.sh   (wired into `composer check-deprecations`)
set -uo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/check-deprecations.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/phel-doom-dep.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tools" "$WORK/vendor/bin" "$WORK/.phel"
cd "$WORK" || exit 2
cp "$GUARD" tools/check-deprecations.sh
printf '{"packages":[{"name":"phel-lang/phel-lang","version":"0.50.0"}]}' > composer.lock
printf '<?php return 1;' > phel-config.php

cat > vendor/bin/phel <<'STUB'
#!/usr/bin/env bash
# Stand-in for `vendor/bin/phel test`, driven by FAKE_MODE. Creates the cache
# directory the way the real compiler does - the script under test never makes
# it, it only decides whether yesterday's may be kept.
[ -n "${PHEL_CACHE_DIR:-}" ] && mkdir -p "$PHEL_CACHE_DIR"
case "${FAKE_MODE:-ok}" in
  ok)    echo "Passed: 10"; echo "Total: 10"; exit 0 ;;
  dep)   echo "Deprecated: Using \"php/new\" is deprecated"; echo "Total: 10"; exit 0 ;;
  fail)  echo "FAIL some-test"; echo "Total: 10"; exit 1 ;;
  empty) echo "nothing ran"; exit 0 ;;
  # Alive until someone signals it. Records its PID so the fixture can reap it:
  # signalling only the script leaves this running, and the command substitution
  # around it then blocks until it exits - two of these turned a 12-second gate
  # step into 72 seconds.
  hang)  echo $$ > hang.pid; sleep 20; exit 0 ;;
esac
STUB
chmod +x vendor/bin/phel

pass=0
fail=0

caches() { ls -d .phel/cache-deprecations-* 2>/dev/null | wc -l | tr -d ' '; }

check() { # check <name> <expected-exit: 0|nonzero> <expected-caches>
  local name="$1" want_rc="$2" want_caches="$3" rc n
  out="$(FAKE_MODE="$MODE" bash tools/check-deprecations.sh 2>&1)"
  rc=$?
  n="$(caches)"
  local ok=1
  if [ "$want_rc" = "0" ] && [ "$rc" -ne 0 ]; then ok=0; fi
  if [ "$want_rc" != "0" ] && [ "$rc" -eq 0 ]; then ok=0; fi
  [ "$n" != "$want_caches" ] && ok=0
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL  $name (exit $rc want $want_rc; caches $n want $want_caches)"
    echo "      ${out//$'\n'/$'\n'      }"
  fi
}

# A clean run leaves its cache behind - that is the entire reason this
# directory exists, and the 14 seconds a warm run saves.
MODE=ok  check "a clean run keeps its cache" 0 1
MODE=ok  check "a second clean run reuses it" 0 1

# ... and a run that FINDS something takes it away, so the next run recompiles
# and reports it again. A gate you can pass by running it twice is worse than
# no gate.
MODE=dep check "a deprecation drops the cache" 1 0
MODE=dep check "and stays red on the retry" 1 0

# A test failure is not a deprecation, but the compile that produced it is
# still half-cached with warnings already emitted.
MODE=ok  check "warm up again" 0 1
MODE=fail check "a suite failure drops the cache" 1 0

# No result line at all: the suite crashed, or never ran.
MODE=ok    check "warm up again" 0 1
MODE=empty check "an empty run drops the cache" 1 0

# Ctrl-C mid-compile is the same hazard, and the quietest: some namespaces are
# compiled and cached, their warnings went to a log nobody reads.
MODE=ok bash tools/check-deprecations.sh >/dev/null 2>&1
if [ "$(caches)" = "1" ]; then
  FAKE_MODE=hang bash tools/check-deprecations.sh >/dev/null 2>&1 &
  hangpid=$!
  # Wait for the stub to actually be running before signalling.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$hangpid" 2>/dev/null || break
    pgrep -P "$hangpid" >/dev/null 2>&1 && break
    perl -e 'select(undef,undef,undef,0.2)'
  done
  kill -INT "$hangpid" $(pgrep -P "$hangpid" 2>/dev/null) 2>/dev/null
  [ -f hang.pid ] && kill -TERM "$(cat hang.pid)" 2>/dev/null
  wait "$hangpid" 2>/dev/null
  rm -f hang.pid
  if [ "$(caches)" = "0" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL  an interrupted run drops the cache (caches $(caches) want 0)"
  fi
else
  fail=$((fail + 1))
  echo "FAIL  an interrupted run drops the cache (setup: no warm cache to start from)"
fi

# SIGTERM is the case only the trap can answer. On SIGINT bash happens to run
# the rest of the script, so the no-result branch below catches it either way -
# a fixture that only proves THAT would pass with the trap deleted (checked).
# On SIGTERM, untrapped bash dies on the spot and the half-filled cache
# survives, which is the fail-open.
MODE=ok bash tools/check-deprecations.sh >/dev/null 2>&1
if [ "$(caches)" = "1" ]; then
  FAKE_MODE=hang bash tools/check-deprecations.sh >/dev/null 2>&1 &
  termpid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$termpid" 2>/dev/null || break
    pgrep -P "$termpid" >/dev/null 2>&1 && break
    perl -e 'select(undef,undef,undef,0.2)'
  done
  kill -TERM "$termpid" 2>/dev/null
  [ -f hang.pid ] && kill -TERM "$(cat hang.pid)" 2>/dev/null
  wait "$termpid" 2>/dev/null
  rm -f hang.pid
  if [ "$(caches)" = "0" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL  a terminated run drops the cache (caches $(caches) want 0)"
  fi
else
  fail=$((fail + 1))
  echo "FAIL  a terminated run drops the cache (setup: no warm cache to start from)"
fi

# A compiler upgrade can deprecate a form that compiled clean yesterday, so the
# old cache is not evidence about the new toolchain.
MODE=ok check "warm up again" 0 1
before="$(ls -d .phel/cache-deprecations-* 2>/dev/null)"
printf '{"packages":[{"name":"phel-lang/phel-lang","version":"0.51.0"}]}' > composer.lock
MODE=ok check "a lockfile change starts a new cache" 0 1
after="$(ls -d .phel/cache-deprecations-* 2>/dev/null)"
if [ "$before" != "$after" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL  a lockfile change starts a new cache (still $after)"
fi

# The same check for the compiler settings, which change what is generated.
before="$after"
printf '<?php return 2;' > phel-config.php
MODE=ok check "a phel-config change starts a new cache" 0 1
after="$(ls -d .phel/cache-deprecations-* 2>/dev/null)"
if [ "$before" != "$after" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL  a phel-config change starts a new cache (still $after)"
fi

# Exactly one cache survives each change: the count assertions above already
# say so, but state it plainly - otherwise every lockfile bump leaves a
# directory behind forever.
mkdir -p .phel/cache-deprecations-deadbeef0000
MODE=ok check "a stale cache is pruned" 0 1

echo "check-deprecations fixtures: $pass passed, $fail failed."
[ "$fail" -eq 0 ] || exit 1
