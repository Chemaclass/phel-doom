#!/usr/bin/env bash
# Render one game frame to a PNG you can actually look at.
#
#   tools/frame-shot.sh <script.phel> <out.png> [cols] [rows]
#
# `script.phel` is any Phel script that writes a rendered frame (raw ANSI)
# to the path given as its first CLI argument - see the example in
# docs/contributing.md. The frame goes through tools/frame-to-html.php,
# which emulates a terminal cell grid so absolutely-positioned overlays
# land where they would on screen, then through headless Chrome.
#
# Why bother: the suite pins bytes and hashes, which proves a frame did
# not CHANGE - never that it looks right. Every visual claim in
# docs/rendering.md (the message line clears the minimap, the telegraph
# sits above the head, the reticle turns red on a target) was verified
# with this, and one "artifact" it turned up was the deliberate :steel
# floor theme showing through the gun's transparent gaps, not a bug.
set -uo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 2

script="${1:-}"
out="${2:-}"
cols="${3:-160}"
rows="${4:-40}"

if [ -z "$script" ] || [ -z "$out" ]; then
  echo "usage: tools/frame-shot.sh <script.phel> <out.png> [cols] [rows]"
  exit 2
fi
[ -f "$script" ] || { echo "frame-shot: no such script: $script"; exit 2; }

chrome=""
for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Chromium.app/Contents/MacOS/Chromium" \
         "$(command -v google-chrome 2>/dev/null)" \
         "$(command -v chromium 2>/dev/null)" \
         "$(command -v chromium-browser 2>/dev/null)"; do
  [ -n "$c" ] && [ -x "$c" ] && { chrome="$c"; break; }
done

tmp="$(mktemp -d "${TMPDIR:-/tmp}/phel-doom-shot.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

PHEL_DOOM_SILENT=1 vendor/bin/phel run "$script" "$tmp/frame.ans" || {
  echo "frame-shot: the script failed; it must write raw ANSI to its first argument."
  exit 1
}
[ -s "$tmp/frame.ans" ] || { echo "frame-shot: the script wrote no frame."; exit 1; }

php tools/frame-to-html.php "$cols" "$rows" < "$tmp/frame.ans" > "$tmp/frame.html" || exit 1

if [ -z "$chrome" ]; then
  # Still useful without a browser: the HTML opens anywhere.
  cp "$tmp/frame.html" "${out%.png}.html"
  echo "frame-shot: no Chrome/Chromium found - wrote ${out%.png}.html instead."
  exit 0
fi

"$chrome" --headless --disable-gpu \
  --screenshot="$out" \
  --window-size=$((cols * 9)),$((rows * 20)) \
  --force-device-scale-factor=2 \
  "file://$tmp/frame.html" >/dev/null 2>&1

[ -s "$out" ] || { echo "frame-shot: Chrome produced no image."; exit 1; }
echo "frame-shot: wrote $out ($(wc -c < "$out") bytes)"
