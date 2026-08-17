#!/usr/bin/env bash
# Attribute frame cost to the render features, by benchmarking the frame with
# each one switched off.
#
# "Render is the bottleneck" has been true here for a long time; WHICH PART of
# render was never written down, and every attempt to find out re-derived the
# same shell juggling. It is worth knowing: the wall texture is ~40% of the
# frame, so a 10% win there is worth more than eliminating the floor entirely.
#
# Two things this gets right that the obvious one-liner does not:
#
#   1. Interleaving. Absolute ms drifts badly as the laptop warms - the same
#      commit read 5.9 ms and 7.5 ms an hour apart in one session. Shares are
#      computed WITHIN a pass, where every config shares a thermal state, and
#      then averaged.
#
#   2. Environment. `env $vars cmd` looks obvious and is silently wrong in zsh,
#      which does not word-split an unquoted variable: `env "A=1 B=1" cmd` sets
#      ONE variable named A to the string "1 B=1". Every flag check here is
#      `=== "1"`, so both flags read as off, the run measures the DEFAULT frame,
#      and the number looks plausible. That produced a phantom "disabling two
#      features is 68% slower than disabling one" before this script existed.
#
#      `set -- $vars` does not fix it - zsh does not split there either
#      (`zsh -c 'vars="A=1 B=1"; set -- $vars; echo $#'` prints 1 where bash
#      prints 2). `eval` does, because it re-parses the string, and the config
#      strings here are literals in this file. run_with() is the one place that
#      applies them, and the self-check runs through it - a check that tests a
#      path the script does not use is decoration.
#
# Usage:
#   tools/bench-flags.sh [passes] [filter]
#   tools/bench-flags.sh            # 2 passes, frame-120x30
#   tools/bench-flags.sh 3 frame-240
set -uo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 2

passes="${1:-2}"
filter="${2:-frame-120}"

# name|VAR=1 ... : the baseline must come first, everything is relative to it.
configs=(
  "baseline|"
  "flat walls (no wall texture)|PHEL_DOOM_FLAT_WALLS=1"
  "flat floor (no floor cast)|PHEL_DOOM_FLAT_FLOOR=1"
  "no sub-pixel (one colour per cell)|PHEL_DOOM_NO_SUBPIXEL=1"
  "texture filter on (mips)|PHEL_DOOM_TEXMIP=1"
)

# Apply a config's assignments in a subshell, then run a command under them.
run_with() { # run_with "A=1 B=1" cmd...
  vars="$1"
  shift
  (
    [ -n "$vars" ] && eval "export $vars"
    "$@"
  )
}

# Self-check: prove a two-variable config really arrives as two variables,
# through the same run_with() the measurements use. If this shell mangles it,
# every number below would be measuring the default frame while claiming
# otherwise.
probe="$(run_with 'PHEL_DOOM_FLAT_WALLS=1 PHEL_DOOM_FLAT_FLOOR=1' \
  php -r 'echo getenv("PHEL_DOOM_FLAT_WALLS"), ",", getenv("PHEL_DOOM_FLAT_FLOOR");')"
if [ "$probe" != "1,1" ]; then
  echo "bench-flags: this shell mangles the env prefix (got '$probe', want '1,1')."
  echo "Every measurement would silently be the default frame. Refusing to run."
  exit 2
fi

bench_us() { # -> microseconds, or empty when the filter matched nothing
  PHEL_DOOM_SILENT=1 vendor/bin/phel bench --filter="$filter" 2>/dev/null |
    awk 'NR>1 && NF>=4 {print $4; exit}' |
    python3 -c '
import re,sys
v=sys.stdin.read().strip()
m=re.match(r"([\d.]+)\s*(ms|μs|us|ns)", v)
if not m: raise SystemExit
n=float(m.group(1)); u=m.group(2)
print(n*1000 if u=="ms" else n/1000 if u=="ns" else n)
'
}

echo "bench-flags: $passes interleaved passes, filter '$filter'"

results=""
for p in $(seq 1 "$passes"); do
  for cfg in "${configs[@]}"; do
    name="${cfg%%|*}"
    vars="${cfg#*|}"
    us="$(run_with "$vars" bench_us)"
    [ -z "$us" ] && { echo "bench-flags: filter '$filter' matched no benchmark."; exit 2; }
    results="${results}${p}|${name}|${us}"$'\n'
  done
  echo "  pass $p done"
done

printf '%s' "$results" | python3 -c '
import sys, collections
rows = [l.split("|") for l in sys.stdin.read().splitlines() if l.strip()]
per_pass = collections.defaultdict(dict)
order = []
for p, name, us in rows:
    per_pass[p][name] = float(us)
    if name not in order:
        order.append(name)
base_name = order[0]

print()
print("%-38s%10s%14s%17s" % ("config", "mean", "vs baseline", "share of frame"))
for name in order:
    vals = [per_pass[p][name] for p in per_pass if name in per_pass[p]]
    mean = sum(vals) / len(vals)
    if name == base_name:
        print("%-38s%9.3fms%14s%17s" % (name, mean / 1000, "-", "-"))
        continue
    # Share is computed per pass, then averaged: a pass shares a thermal state,
    # the run as a whole does not.
    shares = [(per_pass[p][base_name] - per_pass[p][name]) / per_pass[p][base_name] * 100
              for p in per_pass if name in per_pass[p]]
    share = sum(shares) / len(shares)
    delta = [(per_pass[p][name] - per_pass[p][base_name]) / 1000 for p in per_pass if name in per_pass[p]]
    print(f"{name:<38}{mean/1000:>9.3f}ms{sum(delta)/len(delta):>+13.3f}ms{share:>16.1f}%")
print()
print("Share = how much of the frame that feature costs, measured by removing it.")
print("They overlap and do not sum: the floor flag is subsumed by the wall flag")
print("(no point casting a floor texture with textures off), and sub-pixel")
print("sampling is what makes the texture sampling expensive in the first place.")
print("A positive share is a cost removed; a negative one is a feature that pays")
print("for itself (the texture filter samples smaller mips on far walls).")
'
