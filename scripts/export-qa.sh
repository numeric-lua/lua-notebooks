#!/bin/sh
# Headless QA for the static HTML export: build a small notebook, export it
# with tools/export.lua, verify the search script in Chromium, and capture
# light/dark/narrow screenshots.  Screenshots stay in a scratch directory and
# are never committed.
#
# Usage: scripts/export-qa.sh
# Requires: luajit, chromium (or chromium-browser), and optionally ImageMagick.
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${LUANB_QA_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/luanb-export-qa.XXXXXX")}
mkdir -p "$OUT"
OUT=$(CDPATH='' cd -- "$OUT" && pwd)
CHROME=${CHROMIUM:-$(command -v chromium || command -v chromium-browser || true)}
if [ -z "$CHROME" ]; then
  echo "export-qa: chromium is required for screenshots" >&2
  exit 1
fi
command -v luajit >/dev/null 2>&1 || {
  echo "export-qa: luajit is required" >&2
  exit 1
}
cd "$ROOT"

luajit - "$OUT/export-qa.luanb" <<'LUA'
local output = assert(arg[1], "missing fixture path")
package.path = "./?.lua;./?/init.lua;" .. package.path
local Notebook = require("notebook.model")
local Format = require("notebook.format")
local Polar = require("notebook.polar")
local theta, r = {}, {}
for index = 1, 96 do
  local angle = (index - 1) * 2 * math.pi / 96
  theta[index] = angle
  r[index] = math.abs(math.sin(4 * angle))
end
local rows, cols = 96, 96
local values = {}
for row = 1, rows do
  values[row] = {}
  for col = 1, cols do
    values[row][col] = (row - 1) / (rows - 1)
  end
end
local qtheta, qr, qu, qv = {}, {}, {}, {}
for index = 1, 12 do
  local angle = (index - 1) * 2 * math.pi / 12
  qtheta[index] = angle
  qr[index] = 1.5
  qu[index] = math.cos(2 * angle)
  qv[index] = math.sin(2 * angle)
end
local stream_lines = {}
for k = 1, 2 do
  local line, arrows = { theta = {}, r = {} }, {}
  for index = 1, 15 do
    local angle = (k - 1) * math.pi + (index - 1) * 0.25
    local radius = 0.5 + 0.05 * (index - 1) + 0.3 * (k - 1)
    line.theta[index] = angle
    line.r[index] = radius
    if index == 8 then
      local next_angle = angle + 0.25
      local next_radius = radius + 0.05
      local x1, y1 = radius * math.cos(angle), -radius * math.sin(angle)
      local x2 = next_radius * math.cos(next_angle)
      local y2 = -next_radius * math.sin(next_angle)
      arrows[1] = { theta = angle, r = radius,
        angle = math.deg(math.atan2(y2 - y1, x2 - x1)) }
    end
  end
  line.arrows = arrows
  stream_lines[k] = line
end
-- Third line leaves the frame; its rim arrow is clipped and its far arrow is
-- fully outside.  The dashed style pins the shared line-style metadata.
local clip_line = { theta = {}, r = {}, arrows = {
  { theta = 1.45, r = 2.0, angle = 120 },
  { theta = 2.0, r = 3.2, angle = 140 },
} }
for index = 1, 12 do
  local angle = 0.2 + 0.25 * (index - 1)
  clip_line.theta[index] = angle
  clip_line.r[index] = 1.0 + 0.18 * (index - 1)
end
stream_lines[3] = clip_line
local notebook = Notebook.new({ name = "export-qa.luanb", cells = {
  { kind = "markdown", source = table.concat({
    "# Export QA",
    "",
    "Reader-facing search, a checklist, and a polar preview.",
    "",
    "- [x] render task lists",
    "- [ ] copy source",
    "",
    "---",
    "",
    "3. third step",
    "4. fourth step",
    "",
    "~~retired~~ wording",
    "",
    "```lua",
    "print('snippet')",
    "```",
  }, "\n") },
  { kind = "code", source = "return { scene = polar_plot }" },
  { kind = "markdown", source =
    "## Search target\n\nThe word *needle* only appears here." },
  { kind = "code", source = "print('haystack output')",
    output = "haystack output" },
} })
notebook.cells[2].scene = {
  type = "luaplotlib", orientation = "polar", title = "rose curve",
  theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
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
      { kind = "quiver", theta = qtheta, r = qr, u = qu, v = qv,
        scale = 14, pivot = "middle", max_arrows = 12,
        style = { color = "#e45756", linewidth = 1.3, head = 5,
          alpha = 0.9, label = "flow" } },
      { kind = "streamplot",
        theta = { 0, math.pi / 2, math.pi, 3 * math.pi / 2, 2 * math.pi },
        r = { 0.25, 0.75, 1.25, 1.75 },
        lines = stream_lines, periodic = true, density = 1,
        step = 0.08, step_mode = "explicit", resolved_step = 0.08,
        max_steps = 300, max_lines = 16, max_points = 800, head = 6,
        arrow_fraction = 0.35,
        style = { color = "#54a24b", linewidth = 1.4, alpha = 0.9,
          linestyle = "dashed", label = "stream" } },
    },
  },
}
notebook.cells[2].output = "scene returned"
do
  local resolved = Polar.resolve(notebook.cells[2].scene)
  local heatmap = resolved.heatmaps[1]
  assert(heatmap.sampled, "export QA field was not sampled")
  assert(heatmap.sampled_cells <= Polar.HEATMAP_CELL_LIMIT,
    "export QA field exceeded the heatmap cell cap")
  local quiver, stream
  for _, series in ipairs(resolved.series) do
    if series.kind == "quiver" then quiver = series end
    if series.kind == "streamplot" then stream = series end
  end
  assert(quiver ~= nil and quiver.drawn == 12,
    "export QA quiver does not draw twelve arrows")
  assert(stream ~= nil and stream.line_count == 3 and
    stream.arrow_count == 4, "export QA streamplot is incomplete")
  assert(stream.linestyle == "dashed", "export QA stream style was dropped")
  assert(stream.arrow_fraction == 0.35,
    "export QA arrow fraction was dropped")
  local cx, cy, radius = Polar.frame_layout(54, 22, 800 - 20, 320 - 30, false)
  local drawn = Polar.stream_lines(stream, cx, cy, radius, resolved.rmax,
    resolved.theta_zero, resolved.direction)
  local visible_lines, visible_points, visible_runs, visible_arrows = 0, 0, 0,
    0
  for _, line in ipairs(drawn) do
    visible_lines = visible_lines + 1
    visible_points = visible_points + #line.points
    visible_runs = visible_runs + #line.runs
    visible_arrows = visible_arrows + #line.arrows
  end
  assert(visible_lines == 3 and visible_points < stream.point_count,
    "export QA streamplot was not clipped")
  assert(visible_arrows == 3 and visible_runs == 3,
    "export QA visible stream counts are wrong")
  local svg = Format.scene_svg(notebook.cells[2].scene, 800, 320)
  assert(select(2, svg:gsub('class="scene%-polar%-quiver%-arrow"', "")) ==
    quiver.drawn, "export QA quiver arrow count disagrees")
  assert(select(2, svg:gsub('class="scene%-polar%-streamline%-path"', "")) ==
    visible_runs, "export QA streamline count disagrees")
  assert(select(2, svg:gsub('class="scene%-polar%-stream%-arrow"', "")) ==
    visible_arrows, "export QA stream arrow count disagrees")
  assert(svg:find('data-linestyle="dashed"', 1, true) ~= nil,
    "export QA stream style attribute missing")
  assert(svg:find('stroke-dasharray="6 4"', 1, true) ~= nil,
    "export QA stream dash pattern missing")
  assert(svg:find('clip-path="url(#scene-polar-clip-', 1, true) ~= nil,
    "export QA stream clip path missing")
  print(string.format(
    "export-qa field: %d blocks, quiver: %d arrows, streamplot: %d lines, " ..
    "%d visible runs, %d visible points, %d visible arrows",
    heatmap.sampled_cells, quiver.drawn, stream.line_count, visible_runs,
    visible_points, visible_arrows))
end
local handle = assert(io.open(output, "wb"))
handle:write(Format.encode(notebook))
handle:close()
LUA

luajit tools/export.lua "$OUT/export-qa.luanb" "$OUT/export-qa.html"

URL="file://$OUT/export-qa.html"
shoot() {
  name=$1; size=$2; url=$3; shift 3
  "$CHROME" --headless=new --no-sandbox --disable-gpu --hide-scrollbars \
    --user-data-dir="$OUT/profile-$name" --window-size="$size" \
    --virtual-time-budget=2000 --screenshot="$OUT/$name.png" "$@" "$url" \
    >"$OUT/$name.log" 2>&1
  [ -s "$OUT/$name.png" ] || {
    echo "export-qa: missing screenshot $name" >&2
    exit 1
  }
}
shoot export-light 1280,1500 "$URL"
shoot export-dark 1280,1500 "$URL" --force-dark-mode
shoot export-narrow 420,1500 "$URL"
shoot export-filtered 1280,900 "$URL?q=needle"

"$CHROME" --headless=new --no-sandbox --disable-gpu --user-data-dir="$OUT/profile-dom-full" \
  --virtual-time-budget=2000 --dump-dom "$URL" \
  >"$OUT/full.dom.html" 2>"$OUT/full-dom.log"
for needle in 'class="task-list"' 'class="task-list-item done"' \
    '<hr>' '<del>retired</del>' '<ol start="3">' \
    'class="heading-permalink"' 'aria-label="Permalink to Export QA"' \
    'class="copy-code"' 'class="code-line"' 'data-line="1"' \
    'language-lua'; do
  grep -Fq "$needle" "$OUT/full.dom.html" || {
    echo "export-qa: missing $needle in rendered DOM" >&2
    exit 1
  }
done
grep -Fq "Copy" "$OUT/full.dom.html" || {
  echo "export-qa: copy control missing" >&2
  exit 1
}
"$CHROME" --headless=new --no-sandbox --disable-gpu --user-data-dir="$OUT/profile-dom" \
  --virtual-time-budget=2000 --dump-dom "$URL?q=needle" \
  >"$OUT/filtered.dom.html" 2>"$OUT/filtered-dom.log"
grep -Fq "Showing 1 of 4 cells." "$OUT/filtered.dom.html" || {
  echo "export-qa: search did not filter to one cell" >&2
  exit 1
}
"$CHROME" --headless=new --no-sandbox --disable-gpu --user-data-dir="$OUT/profile-dom-kind" \
  --virtual-time-budget=2000 --dump-dom "$URL?kind=figures" \
  >"$OUT/filtered-kind.dom.html" 2>"$OUT/filtered-kind-dom.log"
grep -Fq "Showing 1 of 4 cells." "$OUT/filtered-kind.dom.html" || {
  echo "export-qa: kind filter did not select the figure cell" >&2
  exit 1
}

if command -v magick >/dev/null 2>&1; then
  for image in "$OUT"/export-*.png; do
    deviation=$(magick "$image" -colorspace gray \
      -format '%[fx:standard_deviation]' info:)
    echo "$(basename "$image") sd=$deviation"
    if awk "BEGIN { exit !($deviation < 0.01) }"; then
      echo "export-qa: blank screenshot $image" >&2
      exit 1
    fi
  done
fi

echo "export-qa ok: $OUT"
