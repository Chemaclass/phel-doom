#!/usr/bin/env bash
# Regression fixtures for tools/format-sources.sh.
#
# The script now remembers which files passed `format --dry-run`, so the gate
# stops re-deciding that ~90 untouched files are still formatted (5.1s -> 0.5s).
# Every bug in that memory is a fail-OPEN: an unformatted file skipped because
# the cache says it was fine once. What the fixtures pin:
#
#   the first run checks everything, the second checks nothing
#   an edited file is checked again
#   a FAILED check records nothing, so the retry checks it again
#   a formatter change (composer.lock) starts an empty cache and prunes the old
#   write mode never consults the cache
#   the generated data files stay excluded in both modes
#
# `phel format` is stubbed: this is a test of which files get handed to the
# formatter, not of the formatter. The stub appends its arguments to args.log.
#
# Run: bash tools/format-sources-test.sh   (wired into `composer format-check`)
set -uo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/format-sources.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/phel-doom-fmt-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tools" "$WORK/vendor/bin" "$WORK/src/io/render" "$WORK/tests"
cd "$WORK" || exit 2
cp "$GUARD" tools/format-sources.sh
printf 'lock-v1' > composer.lock

# The real skip list, so a rename in the script shows up here.
printf ';; generated\n' > src/io/render/enemy_sprites_data.phel
printf ';; generated\n' > src/io/render/weapon_sprites_data.phel
printf ';; generated\n' > src/io/render/wall_texture_data.phel
printf ';; generated\n' > src/io/sound_data.phel
printf '(ns app.a)\n' > src/a.phel
printf '(ns app.b)\n' > src/b.phel
printf '(ns app.a-test)\n' > tests/a-test.phel

cat > vendor/bin/phel <<'STUB'
#!/usr/bin/env bash
# Stand-in for `vendor/bin/phel format`. Logs the .phel paths it was asked to
# handle, one per line, and fails when FAKE_FAIL names a file in the batch.
shift            # drop the `format` subcommand
for a in "$@"; do
  case "$a" in
    --*) ;;
    *) echo "$a" >> args.log ;;
  esac
done
if [ -n "${FAKE_FAIL:-}" ]; then
  for a in "$@"; do
    [ "$a" = "$FAKE_FAIL" ] && { echo "1 file(s) need reformatting."; exit 1; }
  done
fi
echo "No files would be reformatted."
exit 0
STUB
chmod +x vendor/bin/phel

pass=0
fail=0

run() { # run [args...] -> checked file list in args.log
  rm -f args.log
  bash tools/format-sources.sh "$@" >/dev/null 2>&1
  return $?
}
checked() { [ -f args.log ] && sort args.log || true; }

expect() { # expect <name> <expected newline-separated list>
  local name="$1" want="$2" got
  got="$(checked)"
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL  $name"
    echo "      want: [${want//$'\n'/, }]"
    echo "      got:  [${got//$'\n'/, }]"
  fi
}

all_sources="$(printf 'src/a.phel\nsrc/b.phel\ntests/a-test.phel')"

# First check has nothing remembered, so it checks every hand-written file -
# and none of the generated ones.
run --dry-run
expect "the first check looks at every hand-written file" "$all_sources"

# Second check has the same content in front of it.
run --dry-run
expect "the second check looks at nothing" ""

# An edit puts that file back in front of the formatter, and only that one.
printf '(ns app.a)\n(def x 1)\n' > src/a.phel
run --dry-run
expect "an edited file is checked again" "src/a.phel"

# A failing check must record nothing: otherwise the file is remembered as
# passing and the next run skips the very thing that failed.
printf '(ns app.b)\n(def   y   2)\n' > src/b.phel
FAKE_FAIL=src/b.phel run --dry-run
rc=$?
if [ "$rc" -ne 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL  a failing check exits non-zero"; fi
expect "the failing file was checked" "src/b.phel"
FAKE_FAIL=src/b.phel run --dry-run
expect "and is checked again on the retry" "src/b.phel"

# Once it passes, it is remembered like any other.
run --dry-run
expect "a fixed file is checked once more" "src/b.phel"
run --dry-run
expect "then remembered" ""

# A formatter upgrade can change what "formatted" means, so nothing carries
# over - and the old cache does not linger.
printf 'lock-v2' > composer.lock
run --dry-run
expect "a formatter change re-checks everything" "$all_sources"
n="$(ls .phel/format-ok-*.txt 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n" = "1" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL  exactly one cache survives a formatter change (found $n)"; fi

# Write mode must never consult the cache: re-formatting a formatted file is
# idempotent, and a cache that could suppress a WRITE is a way to leave a file
# unformatted on disk.
run
expect "write mode formats every file, cache or not" "$all_sources"
run
expect "write mode again, still every file" "$all_sources"

# The skip list is load-bearing: enemy_sprites_data.phel alone took 94.7s of a
# 124s check before it was excluded.
if [ -z "$(checked | grep -E '_data\.phel$')" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL  generated data files stay excluded in write mode"
fi

# A renamed generated file must fail loudly rather than silently handing the
# 95-second file back to every commit.
mv src/io/sound_data.phel src/io/sound_data_renamed.phel
run --dry-run
if [ $? -ne 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL  a renamed generated file is an error"; fi
mv src/io/sound_data_renamed.phel src/io/sound_data.phel

echo "format-sources fixtures: $pass passed, $fail failed."
[ "$fail" -eq 0 ] || exit 1
