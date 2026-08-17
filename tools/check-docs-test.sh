#!/usr/bin/env bash
# Regression fixtures for tools/check-docs.php.
#
# This guard reads prose, which is the easiest place to be confidently wrong:
# a heading slug rule that is nearly GitHub's, a path pattern that also matches
# a sentence. Every case below is markdown the guard has to judge correctly,
# with positive controls so a guard that never fires cannot pass.
#
# Run: bash tools/check-docs-test.sh   (wired into `composer check-docs`)
set -uo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/check-docs.php"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/phel-doom-docs.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/docs/adr" "$WORK/src/io" "$WORK/tools"
cd "$WORK" || exit 2
cp "$GUARD" ./check-docs.php
printf '{"scripts":{"test":"phel test","check-docs":"php tools/check-docs.php"}}' > composer.json
touch src/io/real.phel

pass=0
fail=0

# expect: "broken" = must exit non-zero, "clean" = must exit zero
check() {
  local name="$1" expect="$2"
  local out rc
  out="$(php check-docs.php 2>&1)"
  rc=$?
  if { [ "$expect" = "broken" ] && [ "$rc" -ne 0 ]; } || { [ "$expect" = "clean" ] && [ "$rc" -eq 0 ]; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL  $name (expected $expect, exit $rc)"
    echo "      ${out//$'\n'/$'\n'      }"
  fi
  rm -f docs/*.md docs/adr/*.md README.md
}

# --- fail-open cases: broken claims the guard must not miss ------------------

cat > docs/a.md <<'EOF'
# A
See [the other doc](b.md).
EOF
check "a link to a file that is not there" broken

cat > docs/a.md <<'EOF'
# A
## Pixel-doubled mode (auto, big screens)
Jump to [Pixel-doubling](#pixel-doubling).
EOF
check "a link to a heading that was retitled" broken

cat > docs/a.md <<'EOF'
# A
The bake tool writes `src/io/sound-data` as base64.
EOF
check "a backticked path that does not exist" broken

cat > docs/a.md <<'EOF'
# A
Run `composer benchmarks` to measure.
EOF
check "a composer script that does not exist" broken

cat > docs/a.md <<'EOF'
# A
See [B](b.md#nope).
EOF
cat > docs/b.md <<'EOF'
# B
## Something else
EOF
check "a cross-file link to a heading that is not there" broken

# --- fail-shut cases: correct docs the guard must not flag -------------------

cat > docs/a.md <<'EOF'
# A
See [B](b.md#something-else), and [A itself](#a).
The source is `src/io/real.phel`. Run `composer test`.
EOF
cat > docs/b.md <<'EOF'
# B
## Something else
EOF
check "links, anchors, a real path and a real script" clean

cat > docs/a.md <<'EOF'
# A
Install with `composer install`, then `composer update`.
EOF
check "composer's own commands, which are not scripts" clean

cat > docs/a.md <<'EOF'
# A
## Issue #324 - fixed-centre crosshair
Jump to [it](#issue-324---fixed-centre-crosshair).
EOF
check "a heading whose punctuation the slug drops" clean

cat > docs/a.md <<'EOF'
# A
## Notes
## Notes
Second one is [here](#notes-1).
EOF
check "a repeated heading, which GitHub suffixes" clean

cat > docs/a.md <<'EOF'
# A
```bash
# Notes
php tools/gone.php   # not a heading, not a claim
```
Paths in a code block are transcripts: `src/io/real.phel` is the claim.
EOF
check "a fenced block whose comment looks like a heading" clean

cat > docs/adr/0001-old.md <<'EOF'
# A decision, as it was
It removed `src/core/tier.phel`, which is why it no longer exists.
EOF
cat > docs/a.md <<'EOF'
# A
See [the ADR](adr/0001-old.md).
EOF
check "an ADR naming a file the decision removed" clean

cat > docs/a.md <<'EOF'
# A
Prose about a `world/map` boundary and a ratio of `2/3`.
EOF
check "backticked text that is not a path" clean

cat > README.md <<'EOF'
# phel-doom
Docs live in [docs/a.md](docs/a.md).
EOF
cat > docs/a.md <<'EOF'
# A
EOF
check "a README link into docs/" clean

cat > docs/a.md <<'EOF'
# A
It checks any backticked repo path (`src/...`, `tools/...`) against the tree.
EOF
check "an elided path used as a pattern in prose" clean

echo "check-docs fixtures: $pass passed, $fail failed."
[ "$fail" -eq 0 ] || exit 1
