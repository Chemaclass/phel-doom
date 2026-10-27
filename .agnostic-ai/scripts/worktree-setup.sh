#!/usr/bin/env bash
set -eu

root=$(git rev-parse --show-toplevel)
common=$(git rev-parse --git-common-dir)
main=$(cd "$common/.." && pwd -P)
root=$(cd "$root" && pwd -P)

[ "$root" != "$main" ] || exit 0
[ ! -e "$root/vendor" ] && [ ! -L "$root/vendor" ] || exit 0

for path in vendor composer.lock .phel; do
  if [ -e "$main/$path" ] && [ ! -e "$root/$path" ] && [ ! -L "$root/$path" ]; then
    ln -s "$main/$path" "$root/$path"
  fi
done
