#!/bin/sh
# Pixel-level visual regression using LÖVR's offscreen rgba8 canvas.
# Usage: scripts/visual-baseline.sh [--update]
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SAVE=${LOVR_SAVE_DIR:-$HOME/.local/share/LOVR/lua-notebooks}
cd "$ROOT"
mkdir -p tests/visual/baseline
UPDATE=${1:-}
for cell in 4 6 7; do
  rm -rf "$SAVE/screenshots"
  LUANB_QA_THEME=dark LUANB_QA_CELL=$cell LUANB_QA_SCROLL=0 LUANB_QA_SCREENSHOT=1 lovr . >/tmp/luanb-visual-$cell.log 2>&1 &
  APP=$!
  SHOT=
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 1
    SHOT=$(find "$SAVE/screenshots" -name 'notebook-*.png' 2>/dev/null | head -1)
    [ -n "$SHOT" ] && break
  done
  if [ -z "$SHOT" ]; then
    kill "$APP" 2>/dev/null || true
    echo "no screenshot for cell $cell" >&2
    exit 1
  fi
  # Normalize to a small, stable image; the source canvas is 906x1040 here.
  magick "$SHOT" -resize 50% -strip /tmp/luanb-visual-$cell.png
  kill "$APP" 2>/dev/null || true
  wait "$APP" 2>/dev/null || true
  BASE=tests/visual/baseline/cell$cell.png
  if [ "$UPDATE" = "--update" ]; then
    cp /tmp/luanb-visual-$cell.png "$BASE"
    echo "updated $BASE"
  else
    [ -f "$BASE" ] || { echo "missing baseline $BASE" >&2; exit 1; }
    DIFF=$(magick compare -metric AE /tmp/luanb-visual-$cell.png "$BASE" null: 2>&1 | awk '{print $1}')
    echo "cell=$cell diff=$DIFF"
    if [ "${DIFF%.*}" -gt 800 ]; then
      echo "visual regression for cell $cell" >&2
      exit 1
    fi
  fi
done
echo "pixel baseline check ok"
