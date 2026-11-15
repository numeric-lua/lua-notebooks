#!/bin/sh
# Wayland visual smoke: launch each QA cell, capture the notebook window area,
# and check that the rendered surface is not a flat/blank region.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
for cell in 3 4 6 7; do
  LUANB_QA_CELL=$cell lovr . >/tmp/luanb-visual-$cell.log 2>&1 &
  APP=$!
  sleep 4
  grim /tmp/luanb-visual-$cell-full.png
  kill "$APP" 2>/dev/null || true
  wait "$APP" 2>/dev/null || true
  magick /tmp/luanb-visual-$cell-full.png -crop 940x1080+0+0 +repage \
    /tmp/luanb-visual-$cell.png
  W=$(magick identify -format '%w' /tmp/luanb-visual-$cell.png)
  H=$(magick identify -format '%h' /tmp/luanb-visual-$cell.png)
  SD=$(magick /tmp/luanb-visual-$cell.png -colorspace gray \
    -format '%[fx:standard_deviation]' info:)
  echo "cell=$cell size=${W}x${H} sd=$SD"
  if [ "$W" -ne 940 ] || [ "$H" -ne 1080 ]; then
    echo "visual smoke failed: capture too small" >&2
    exit 1
  fi
  if awk "BEGIN { exit !($SD < 0.01) }"; then
    echo "visual smoke failed: blank capture for cell $cell" >&2
    exit 1
  fi
done
echo "visual smoke ok"
