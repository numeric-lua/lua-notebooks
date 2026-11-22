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
local rows, cols = 96, 96
local values = {}
for row = 1, rows do
  values[row] = {}
  for col = 1, cols do
    values[row][col] = (row - 1) / (rows - 1)
  end
end
local quiver_theta, quiver_r, quiver_u, quiver_v = {}, {}, {}, {}
for i = 1, 24 do
  local a = (i - 1) * 2 * math.pi / 24
  quiver_theta[i] = a
  quiver_r[i] = 1.6
  quiver_u[i] = math.cos(3 * a)
  quiver_v[i] = math.sin(3 * a)
end
local stream_lines = {}
for k = 1, 2 do
  local line, arrows = { theta = {}, r = {} }, {}
  for i = 1, 20 do
    local a = (k - 1) * math.pi + (i - 1) * 0.22
    local radius = 0.5 + 0.05 * (i - 1) + 0.3 * (k - 1)
    line.theta[i] = a
    line.r[i] = radius
    if i == 10 then
      local na = a + 0.22
      local nr = radius + 0.05
      local x1, y1 = radius * math.cos(a), -radius * math.sin(a)
      local x2, y2 = nr * math.cos(na), -nr * math.sin(na)
      arrows[1] = { theta = a, r = radius,
        angle = math.deg(math.atan2(y2 - y1, x2 - x1)) }
    end
  end
  line.arrows = arrows
  stream_lines[k] = line
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
    heatmaps = { {
      rows = rows, cols = cols, values = values,
      vmin = 0, vmax = 1, rmin = 0, rmax = 2,
      theta_min = 0, theta_max = 2 * math.pi,
      alpha = 1, label = "density", colorbar = true,
    } },
    contours = { {
      rows = rows, cols = cols,
      levels = {
        { level = 0.25, segments = {
          { 0, 0.8, 1.2, 1.2 }, { 2.4, 0.8, 3.8, 1.2 } } },
        { level = 0.75, segments = {
          { 0.4, 1.2, 1.6, 1.6 }, { 2.8, 1.0, 4.2, 1.4 } } },
      },
      labels = true,
      style = { color = "#ffd166", linewidth = 1.5, alpha = 0.95,
        linestyle = "dashed", label = "isolines" },
    } },
    colorbar = { orientation = "vertical", vmin = 0, vmax = 1,
      ticks = { 0, 0.5, 1 }, label = "density" },
    series = {
      { kind = "line", theta = theta, r = r,
        style = { color = "#1f77b4", label = "rose" } },
      { kind = "scatter", theta = { 0, math.pi / 2, math.pi },
        r = { 1, 2, 1 },
        style = { color = "#ff7f0e", radius = 5 } },
      { kind = "bar", theta = { math.pi / 4 }, r = { 1.5 },
        widths = { 0.45 }, colors = { "#2ca02c" } },
      { kind = "quiver", theta = quiver_theta, r = quiver_r,
        u = quiver_u, v = quiver_v, scale = 12, pivot = "middle",
        max_arrows = 12,
        style = { color = "#e45756", linewidth = 1.4, head = 4,
          alpha = 0.95, label = "flow" } },
      { kind = "streamplot",
        theta = { 0, math.pi / 2, math.pi, 3 * math.pi / 2, 2 * math.pi },
        r = { 0.25, 0.75, 1.25, 1.75 },
        lines = stream_lines, periodic = true, density = 1,
        step = 0.08, step_mode = "explicit", resolved_step = 0.08,
        max_steps = 300, max_lines = 16, max_points = 800, head = 6,
        style = { color = "#54a24b", linewidth = 1.4, alpha = 0.9,
          label = "stream" } },
    },
  },
} }
]]
-- Check the cap before launching the app: the same source must resolve to a
-- sampled field and the SVG must contain exactly that many block cells.
do
  local chunk = assert(loadstring(source))
  setfenv(chunk, { math = math })
  local result = chunk()
  local Polar = require("notebook.polar")
  local resolved = Polar.resolve(result.scene)
  local heatmap = resolved.heatmaps[1]
  assert(heatmap.sampled, "polar QA fixture was not sampled")
  assert(heatmap.sampled_cells <= Polar.HEATMAP_CELL_LIMIT,
    "polar QA fixture exceeded the heatmap cell cap")
  local quiver, stream
  for _, series in ipairs(resolved.series) do
    if series.kind == "quiver" then quiver = series end
    if series.kind == "streamplot" then stream = series end
  end
  assert(quiver ~= nil and quiver.drawn > 0,
    "polar QA fixture has no quiver arrows")
  assert(quiver.stride == 2 and quiver.drawn == 12,
    "polar QA quiver was not decimated to twelve arrows")
  local svg = Format.scene_svg(result.scene, 800, 320)
  local exported = select(2, svg:gsub('class="scene%-polar%-heatmap%-cell"', ""))
  assert(exported == heatmap.sampled_cells,
    "live and exported block counts disagree")
  local exported_quiver = select(2,
    svg:gsub('class="scene%-polar%-quiver%-arrow"', ""))
  assert(exported_quiver == quiver.drawn,
    "live and exported quiver arrow counts disagree")
  assert(stream ~= nil and stream.line_count == 2 and
    stream.arrow_count == 2, "polar QA fixture has no streamplot lines")
  local exported_stream = select(2,
    svg:gsub('class="scene%-polar%-streamline%-path"', ""))
  assert(exported_stream == stream.line_count,
    "live and exported streamline counts disagree")
  local exported_stream_arrows = select(2,
    svg:gsub('class="scene%-polar%-stream%-arrow"', ""))
  assert(exported_stream_arrows == stream.arrow_count,
    "live and exported stream arrow counts disagree")
  print(string.format("polar-qa field: %dx%d -> %d blocks", heatmap.rows,
    heatmap.cols, heatmap.sampled_cells))
  print(string.format("polar-qa quiver: %d arrows -> %d drawn", quiver.count,
    quiver.drawn))
  print(string.format("polar-qa streamplot: %d lines, %d arrows",
    stream.line_count, stream.arrow_count))
end
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
LUANB_QA_SCROLL=${LUANB_QA_SCROLL:-620} \
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
