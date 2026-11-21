#!/bin/sh
# Live polar QA: build a one-cell notebook, run it through the LÖVR app, and
# capture the offscreen screenshot.  The capture stays in a scratch directory;
# it is never committed.  Use this to verify ui/plot.lua's polar path on a
# machine with a display (the app renders to an offscreen canvas first).
#
# Usage: scripts/polar-qa.sh
# Requires: luajit, lovr, and optionally ImageMagick for the blank check.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${LUANB_QA_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/luanb-polar-qa.XXXXXX")}
mkdir -p "$OUT"
OUT=$(CDPATH='' cd -- "$OUT" && pwd)
# Keep the throwaway notebook and LÖVR session/screenshots out of the user's
# save directory so repeated QA runs never restore this fixture.
QA_HOME="$OUT/home"
SAVE="$QA_HOME/.local/share/LOVR/lua-notebooks"
mkdir -p "$SAVE"
cd "$ROOT"

command -v luajit >/dev/null 2>&1 || {
  echo "polar-qa: luajit is required" >&2
  exit 1
}
command -v lovr >/dev/null 2>&1 || {
  echo "polar-qa: lovr is required" >&2
  exit 1
}
rm -rf "$SAVE/screenshots"

luajit - "$OUT/polar-live.luanb" <<'LUA'
local output = assert(arg[1], "missing fixture path")
package.path = "./?.lua;./?/init.lua;" .. package.path
local Notebook = require("notebook.model")
local Format = require("notebook.format")
local source = [[
local theta, r = {}, {}
for i = 1, 96 do
  local a = (i - 1) * 2 * math.pi / 96
  theta[i] = a
  r[i] = 1 + 0.8 * math.sin(4 * a)
end
return { scene = {
  type = "luaplotlib", orientation = "polar", title = "polar QA",
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" },
      { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 0.5, label = "0.5" }, { value = 1, label = "1" },
      { value = 1.5, label = "1.5" }, { value = 2, label = "2" },
    },
    series = {
      { kind = "line", theta = theta, r = r,
        style = { color = "#1f77b4", label = "rose" } },
      { kind = "scatter", theta = { 0, math.pi / 2, math.pi },
        r = { 1, 2, 1 },
        style = { color = "#ff7f0e", radius = 5 } },
      { kind = "bar", theta = { math.pi / 4 }, r = { 1.5 },
        widths = { 0.45 }, colors = { "#2ca02c" } },
    },
  },
} }
]]
local notebook = Notebook.new({ name = "polar-live.luanb", cells = {
  { kind = "code", source = source },
} })
local handle = assert(io.open(output, "wb"))
handle:write(Format.encode(notebook))
handle:close()
LUA

LOG="$OUT/lovr.log"
HOME="$QA_HOME" \
XDG_DATA_HOME="$QA_HOME/.local/share" \
XDG_CONFIG_HOME="$QA_HOME/.config" \
XDG_CACHE_HOME="$QA_HOME/.cache" \
LUANB_QA_THEME=${LUANB_QA_THEME:-dark} \
LUANB_QA_UI_SCALE=1 \
LUANB_QA_SCROLL=0 \
LUANB_QA_CELL=1 \
LUANB_QA_SCREENSHOT=1 \
LUANB_QA_SCREENSHOT_AFTER=${LUANB_QA_SCREENSHOT_AFTER:-4} \
  lovr . "$OUT/polar-live.luanb" >"$LOG" 2>&1 &
APP=$!

cleanup() {
  kill "$APP" 2>/dev/null || true
  wait "$APP" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

SHOT=
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  sleep 0.5
  SHOT=$(find "$SAVE/screenshots" -name 'notebook-*.png' 2>/dev/null | head -1)
  [ -n "$SHOT" ] && break
  if ! kill -0 "$APP" 2>/dev/null; then break; fi
done

if [ -z "$SHOT" ]; then
  echo "polar-qa: no screenshot produced; app log:" >&2
  cat "$LOG" >&2
  exit 1
fi
cp "$SHOT" "$OUT/polar-live.png"

if command -v magick >/dev/null 2>&1; then
  SIZE=$(magick identify -format '%wx%h' "$OUT/polar-live.png")
  SD=$(magick "$OUT/polar-live.png" -colorspace gray \
    -format '%[fx:standard_deviation]' info:)
  echo "polar-live.png size=$SIZE sd=$SD"
  if awk "BEGIN { exit !($SD < 0.01) }"; then
    echo "polar-qa: blank screenshot" >&2
    exit 1
  fi
else
  echo "polar-live.png captured (ImageMagick not installed; no blank check)"
fi

echo "polar-qa ok: $OUT/polar-live.png"
