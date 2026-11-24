# Lua Notebooks · Web

A dependency-free browser front-end for the remote LuaJIT kernel. It uses
only the native browser WebSocket, Canvas, and WebGL APIs — no Emscripten,
LÖVR, threads, COOP/COEP, or build step.

## Run

Start the kernel gateway from the repository root:

```sh
LUA_PATH="$PWD/?.lua;$PWD/?/init.lua;;" \
  luajit scripts/kernel-gateway.lua --port 8765
```

Serve this directory with the dependency-free Lua server:

```sh
luajit webapp/serve.lua --port 8010
```

Open:

```text
http://127.0.0.1:8010/
```

The default WebSocket URL is `ws://127.0.0.1:8765`. Override it with:

```text
http://127.0.0.1:8010/?ws=ws://127.0.0.1:9000
```

or with the settings button in the top bar.

## What works

- code and markdown cells, clickable Markdown task-list checkboxes, nested
  lists, pipe tables with alignment, definition lists, italic emphasis, grouped
  and nested blockquotes and callouts, thematic
  breaks, strikethrough, highlight (`==text==`), bare `http(s)://` autolinks,
  backslash-escaped punctuation, ordered-list start numbers, numbered
  footnotes with endnote backlinks, local notebook persistence, `.luanb`
  import/export;
- Shift+Enter / Ctrl+Enter execution;
- stdout, returned values, errors;
- kernel widgets: sliders, buttons, checkboxes, selects, text, numbers,
  progress, labels;
- `star_nest` shader widgets in an animated local WebGL canvas;
- `luaplotlib` Cartesian line, scatter, bar, and histogram scenes with axes,
  grid, titles/labels, categorical ticks, explicit bar widths, and the same
  800/400-point line/scatter sampling caps as the static export;
- polar `luaplotlib` line, scatter, bar, heatmap, contour, quiver, and
  streamplot scenes on the shared circular frame: r rings, theta spokes,
  `theta_zero`/`theta_direction`, an explicit or observed `rmax`, clamped
  radii, short tick labels, wide or negative-radius bar wedges, annular heatmap
  blocks with the shared viridis palette, bounded sampling for fields above
  4096 cells, a stepped vertical colourbar, subdivided contour isolines with
  optional level labels, clipped quiver shaft/head glyphs with shared scaling,
  pivot, normalization, and arrow decimation, and streamplot polylines cut at
  the frame with clipped mid-line arrow heads, dashed/dotted/`none` strokes,
  and source/visible point/run/arrow counters;
- `cube` and `grid` scene strings as local canvas drawings;
- run all, kernel restart, auto-reconnect.

## Deliberate limits

- only the built-in `star_nest` shader preset renders in the browser. Inline
  LÖVR shader source and other preset names show a fallback message instead of
  throwing; the full shader editor/renderer stays in the LÖVR desktop host;
- arbitrary LÖVR scene tables are not rendered, only `luaplotlib` and the
  built-in `cube`/`grid` strings;
- markdown math is displayed as styled source rather than typeset TeX;
- the gateway is a loopback development service with no authentication or
  sandboxing. Use TLS, authentication, and per-session isolation before
  exposing it.

## Architecture

```text
webapp/  (HTML + ES modules + Canvas/WebGL)
    │  native WebSocket JSON
    ▼
scripts/kernel-gateway.lua
    └── kernel/engine.lua  (LuaJIT + FFI libraries)
```

The front-end speaks the same `open` / `run` / `widget` / `restart` protocol as
`RemoteSupervisor`, so the desktop LÖVR host and the browser share one kernel
contract.

## Scene parity

`webapp/js/polar.js` mirrors the dependency-free `notebook/polar.lua` geometry
used by the desktop viewport and the HTML export: rmax fallback, y-down
projection, tick filtering and fallbacks, label limits, sample caps,
point-radius clamps, bar sectors, quiver arrows, and streamplot polyline/arrow
clipping, dash patterns, and source/visible counters. The fixture at
`webapp/tests/fixtures/polar-parity.json` is read by both `tests/polar.lua` and
`webapp/tests/polar.test.mjs`, so a geometry drift on either side fails a
suite.

Cartesian scenes also use the export's palette, explicit bar widths, bar and
histogram extents in the data bounds, and its 800/400 sampling caps. Polar
heatmaps, contours, and colourbars use the same `field_scene` fixture in
`webapp/tests/fixtures/polar-parity.json`, so cell colours, projected cell
radii, contour subdivision, labels, colourbar geometry, and compact tick text
are pinned across the Lua and JavaScript implementations. The
`large_field_scene` fixture pins the 4096-cell sampling cap, block spans, and
first/last block geometry for a 65x65 field, the `quiver_scene` fixture pins
explicit scale, pivot, projection, and per-arrow angle/tail/tip/neck geometry,
the `streamplot_scene` fixture pins grid metadata, integrated line points, and
mid-line arrow heads, the `streamplot_clip_scene` fixture pins frame-clipped
runs, rim arrow polygons, dashed style, and `arrow_fraction`, and
`large-polar-field`, `polar-quiver`, `polar-streamplot`, and
`polar-streamplot-clip` are part of the headless Chromium scene matrix. Rendering
stays Canvas 2D; the browser never needs a GPU or a LÖVR build.

## Tested

The Node suite and the headless browser check run without npm packages:

```sh
make test-webapp   # scene geometry, draw calls, notebook import/export
make qa-webapp     # Chromium pixel check for the whole scene matrix
```

`scripts/scene-qa.sh` serves this directory with `webapp/serve.lua`, renders
the fixture matrix in headless Chromium, and checks each canvas for a non-blank
frame and series-colour pixels. It uses `getImageData`, so the check sees the
real Canvas output instead of only the source calls.

Validated in Chromium against a local gateway:

- notebook loaded and opened the kernel;
- `print(...); return 6*7` produced the captured output and `42`;
- widgets created and a button click returned `pong`;
- a `star_nest` shader widget rendered and animated in WebGL;
- polar, large sampled polar field, polar quiver, polar streamplot, clipped
  dashed polar streamplot, Cartesian, histogram, categorical, cube, and grid
  canvases rendered;
- no page exceptions.


## Gateway token

If the gateway is started with `--token secret`, use a URL that includes the
token:

```text
ws://127.0.0.1:8765/?token=secret
```

The browser sends the token in the WebSocket upgrade query. Unauthorized
upgrades receive HTTP 401 and the front-end reports the connection error.
