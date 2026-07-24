#!/usr/bin/env bash
set -euo pipefail

# Build the phel-doom PHAR: a single-file, self-contained executable game.
#
# Compile the project to out/, then bundle out/ + the whole vendor tree into a
# signed, compressed PHAR (see build-phar.php). vendor/ ships as-is, so the
# working tree is never mutated and there is nothing to restore. The reported
# version comes from `version` in src/core/version.phel (bumped by
# tools/release.sh at release time).
#
# Usage: build/phar.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_SCRIPT="$SCRIPT_DIR/build-phar.php"
PHAR_FILE="$SCRIPT_DIR/out/phel-doom.phar"

error() { echo "Error: $*" >&2; exit 1; }

echo "🔨  Compiling project..."
(cd "$REPO_ROOT" && vendor/bin/phel build --no-cache) || error "phel build failed"

echo "📦  Packaging PHAR..."
php -d phar.readonly=0 "$BUILD_SCRIPT" "$REPO_ROOT" || error "PHAR build failed"
[[ -x "$PHAR_FILE" ]] || error "PHAR was not created or is not executable: $PHAR_FILE"

echo "📍  Final Location:   $PHAR_FILE"
