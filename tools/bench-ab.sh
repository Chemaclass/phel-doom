#!/usr/bin/env bash
# Interleaved A/B benchmark against another git ref.
#
# Why this exists: a single `composer bench` reading on this machine
# drifts far more than most changes are worth. Measured in one sitting,
# the SAME commit read 4.65 ms, 5.09 ms and 6.91 ms as the laptop warmed
# up - so "run the old one, then run the new one" can report a 20%
# regression or a 10% win for code that did not change. Both wrong
# conclusions were drawn from exactly that method before this script
# existed.
#
# Interleaving removes the drift: A and B alternate back to back, so
# each pair shares a thermal state, and the per-pair deltas are averaged.
# The sign being consistent across pairs is the signal; a single pair is
# still worth nothing.
#
# Usage:
#   tools/bench-ab.sh <ref> [pairs] [filter]
#   tools/bench-ab.sh v0.17.0            # 3 pairs, frame-120 rows
#   tools/bench-ab.sh main 5 cast        # 5 pairs, cast rows
#
# The working tree must be clean: this checks out `ref` in place and
# restores your branch afterwards (including on Ctrl-C).
set -uo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 2

ref="${1:-}"
pairs="${2:-3}"
filter="${3:-frame-120}"

if [ -z "$ref" ]; then
  echo "usage: tools/bench-ab.sh <ref> [pairs] [filter]"
  exit 2
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "bench-ab: working tree is dirty - commit or stash first."
  echo "This script checks refs out in place; it will not risk your edits."
  exit 2
fi

git rev-parse --verify --quiet "$ref^{commit}" >/dev/null || {
  echo "bench-ab: '$ref' is not a commit"; exit 2
}

here="$(git rev-parse --abbrev-ref HEAD)"
[ "$here" = "HEAD" ] && here="$(git rev-parse HEAD)"

restore() { git checkout -q "$here" 2>/dev/null; }
trap restore EXIT INT TERM

run_bench() {
  # One row per benchmark: "<name> <mean-with-unit>"
  PHEL_DOOM_SILENT=1 vendor/bin/phel bench --filter="$filter" 2>/dev/null |
    awk 'NR>1 && NF>=4 {print $1, $4}'
}

# Collect into "name<TAB>a-us<TAB>b-us" lines, one file per side.
a_file="$(mktemp)"; b_file="$(mktemp)"
trap 'rm -f "$a_file" "$b_file"; restore' EXIT INT TERM

to_us() { # "5.497ms" / "83.815μs" / "751ns" -> microseconds
  python3 - "$1" <<'PY'
import re,sys
v=sys.argv[1]
m=re.match(r'([\d.]+)\s*(ms|μs|us|ns)', v)
if not m: print(0); raise SystemExit
n=float(m.group(1)); u=m.group(2)
print(n*1000 if u=='ms' else n/1000 if u=='ns' else n)
PY
}

echo "bench-ab: $ref vs $here, $pairs interleaved pairs, filter '$filter'"
for i in $(seq 1 "$pairs"); do
  git checkout -q "$ref"
  while read -r name val; do echo "$name $(to_us "$val")" >> "$a_file"; done < <(run_bench)
  git checkout -q "$here"
  while read -r name val; do echo "$name $(to_us "$val")" >> "$b_file"; done < <(run_bench)
  printf "  pair %d done\n" "$i"
done

python3 - "$a_file" "$b_file" "$ref" "$here" <<'PY'
import sys, collections
def load(p):
    d=collections.defaultdict(list)
    for line in open(p):
        name, val = line.rsplit(None, 1)
        d[name].append(float(val))
    return d
a, b, ref, here = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3], sys.argv[4]
if not a or not b:
    print("bench-ab: no rows measured - does the filter match anything?"); raise SystemExit(2)
print()
w = max(14, len(ref) + 2, len(here) + 2)
print(f"{'benchmark':<46}{ref:>{w}}{here:>{w}}{'delta':>9}")
for name in sorted(a):
    if name not in b: continue
    xs, ys = a[name], b[name]
    n = min(len(xs), len(ys))
    # Paired: average the per-pair ratio, not the ratio of averages, so
    # a hot pair and a cold pair each contribute their own comparison.
    deltas = [(ys[i]-xs[i])/xs[i]*100 for i in range(n)]
    mean = sum(deltas)/n
    same_sign = all(d > 0 for d in deltas) or all(d < 0 for d in deltas)
    flag = "" if same_sign else "  (mixed signs - noise)"
    print(f"{name.split('/')[-1]:<46}{sum(xs)/len(xs):>{w-2}.1f}us{sum(ys)/len(ys):>{w-2}.1f}us{mean:>8.1f}%{flag}")
print()
print("A consistent sign across every pair is the signal. Mixed signs, or a")
print("delta under a few percent on one pair, is the machine, not the code.")
PY
