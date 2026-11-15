#!/bin/sh
# Wayland/Hyprland physical-input smoke.  Requires ydotool/ydotoold, grim, and
# an accessible /dev/uinput.  Not part of `make test` because it needs a seat.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SOCKET=${YDOTOOL_SOCKET:-/tmp/luanb-ydotool.sock}
if [ ! -S "$SOCKET" ]; then
  ydotoold --socket-path "$SOCKET" >/tmp/luanb-ydotoold.log 2>&1 &
  sleep 1
fi
export YDOTOOL_SOCKET="$SOCKET"
cd "$ROOT"
lovr . >/tmp/luanb-input-smoke.log 2>&1 &
APP=$!
trap 'kill "$APP" 2>/dev/null || true' EXIT
sleep 3
for _ in 1 2 3 4 5 6; do
  ydotool key 108:1 108:0
  sleep 0.15
done
sleep 1
grim /tmp/luanb-input-a.png
sleep 1
grim /tmp/luanb-input-b.png
kill "$APP" 2>/dev/null || true
trap - EXIT
DIFF=$(magick compare -metric AE /tmp/luanb-input-a.png /tmp/luanb-input-b.png null: 2>&1 | awk '{print $1}')
echo "input diff pixels: $DIFF"
if [ "${DIFF%.*}" -gt 5000 ]; then
  echo "input smoke failed: scroll or animation unstable" >&2
  exit 1
fi
echo "physical input smoke ok"
