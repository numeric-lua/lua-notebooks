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
local theta, r = {}, {}
for index = 1, 96 do
  local angle = (index - 1) * 2 * math.pi / 96
  theta[index] = angle
  r[index] = math.abs(math.sin(4 * angle))
end
local notebook = Notebook.new({ name = "export-qa.luanb", cells = {
  { kind = "markdown", source =
    "# Export QA\n\nReader-facing search and a polar preview." },
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
    series = {
      { kind = "line", theta = theta, r = r,
        style = { color = "#1f77b4", label = "rose" } },
    },
  },
}
notebook.cells[2].output = "scene returned"
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
