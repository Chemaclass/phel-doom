#!/usr/bin/env bash
set -eu

root=$(git rev-parse --show-toplevel)
common=$(git rev-parse --git-common-dir)
main=$(cd "$common/.." && pwd -P)
root=$(cd "$root" && pwd -P)

[ "$root" != "$main" ] || exit 0
[ ! -e "$root/vendor" ] && [ ! -L "$root/vendor" ] || exit 0
[ -d "$main/vendor" ] && [ -f "$main/composer.lock" ] || exit 0

# A shared vendor/ is only safe while both checkouts require the same packages.
if ! cmp -s "$main/composer.json" "$root/composer.json"; then
  echo "composer.json differs from the main checkout; run composer install in this worktree." >&2
  exit 0
fi

[ -e "$root/composer.lock" ] || cp "$main/composer.lock" "$root/composer.lock"
ln -s "$main/vendor" "$root/vendor"
