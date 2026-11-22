# Static export

**Export notebook as HTML** in the command palette writes a single
self-contained file under the LÖVR save directory:

```text
exports/<notebook-name>.html
```

There are no external stylesheets, fonts, scripts, or image files. Open the
file directly from disk or serve it as a static page. The optional reader
search is a small inline script; the document is still complete and readable
with JavaScript disabled.

## Document shape

The exported document is meant to be read, linked, and printed, not just
dumped:

- `<meta name="viewport">`, description, color-scheme, generator, and Open
  Graph title/description elements;
- a header with the notebook title, kernel, cell/figure/widget counts, and a
  reader search/filter bar when JavaScript is available;
- a sticky `<nav class="toc">` table of contents built from Markdown headings,
  with GitHub-style unique anchors (`intro`, `intro-2`, …);
- a figures index that links to each exported scene;
- one `<section class="cell" id="cell-N">` per cell with a permalink and a
  normalized `data-search` projection;
- styled source, output, and error blocks;
- a backlinks list computed from `[[wiki links]]` across the open notebooks;
- a footer with cell, heading, and tag counts.

The stylesheet follows `prefers-color-scheme` for light/dark rendering and
includes a print stylesheet that hides navigation, the search bar, and
page-break guards.

## Search and filter

When JavaScript runs, the header exposes a case-insensitive full-text search
and a cell-kind filter:

- search terms are split on whitespace and **all** terms must appear in a cell.
  The index covers source, output, error text, scene titles/types/series
  labels, and widget labels; Markdown link destinations are not searchable
  because they are not rendered as text;
- the kind filter offers **All cells**, **Code cells**, **Markdown cells**, and
  **Figure cells** (cells with a scene output);
- `/` focuses the search box, Escape clears the query and filter, and the
  status line reports how many cells are visible;
- matching cells stay in document order, and table-of-contents links for
  hidden cells are hidden too;
- `?q=term` and `?kind=code|markdown|figures` prefill the controls, which makes
  shareable filtered links and headless QA possible;
- without JavaScript the controls are hidden and every cell remains visible.

Cells carry `data-search`, `data-kind`, and, when they own a scene,
`data-has-scene` attributes so the inline script never has to re-render or
parse the page.

## Figures and widgets

Scene outputs become `<figure class="scene" id="figure-N">` elements:

| scene | static representation |
| --- | --- |
| `luaplotlib` `line` | SVG polyline, sampled to at most 800 points |
| `luaplotlib` `scatter` | SVG circles, sampled to at most 400 points |
| `luaplotlib` `bar` | SVG rectangles |
| `luaplotlib` `hist` | SVG rectangles from edges/counts |
| polar `line`/`scatter` | SVG polyline/circles on a circular frame |
| polar `bar` | SVG wedge paths on the same frame |
| polar `heatmap` | SVG annular/pie cells with the shared viridis-like palette |
| polar `contour` | subdivided SVG isolines with optional level labels |
| polar colourbar | stepped vertical bar with compact tick labels and title |
| `"cube"` | inline isometric cube glyph |
| `"grid"` | inline perspective grid glyph |
| other table/extension scene | generic framed glyph |

Polar scenes use the luaplotlib IR shape
(`orientation = "polar"`, data under `scene.polar`) and honour
`polar.rmax`, `polar.theta_zero`, `polar.theta_direction`,
`polar.theta_ticks`, and `polar.r_ticks`. Missing ticks fall back to four
rings and twelve spokes; a missing `rmax` uses the largest absolute radius in
the data. Out-of-range radii clamp to the frame so the preview never overflows.
Tick labels are escaped and long labels are omitted rather than clipped.

Polar heatmaps map matrix rows from `rmin` to `rmax` and columns across
`theta_min` to `theta_max`. Each cell becomes an annular sector (or a pie
sector when `rmin` is zero); a full-turn ring is split into convex wedges so
the same geometry works in SVG and in LÖVR's polygon path. Matrix values are
mapped through the same viridis-like anchors in the export, the live viewport,
and the browser, and non-finite cells fall back to `vmin`. A heatmap that sets
`colorbar = true` reserves a column outside the circular frame for a stepped
vertical bar, its compact numeric ticks, and an optional rotated title.

Polar contours consume the data-space `(theta, r)` segments emitted by
luaplotlib. Each marching-squares edge is subdivided in angular and radial
space before projection, so long isolines read as spirals rather than chords.
`labels = true` places at most one compact level label per contour level on the
segment farthest from the origin and clamps it inside the frame.

The live viewport consumes the same IR. `notebook/polar.lua` is the shared,
LÖVR-free geometry module behind both renderers: it resolves rmax, projects
y-down screen coordinates, filters tick sets, applies the 800/400 sample caps
and short-label rules, and splits wide/negative-radius bars into wedge sectors.
The live frame uses the same circular frame and tick placement, so the export
is a faithful sketch rather than a separate implementation. The SVG itself is
still deterministic and not a raster of the live renderer; animated or custom
extension surfaces need the desktop app. Interactive widgets are not executed
in the export; they are listed as static placeholders.

The browser front-end described in [web.md](web.md) is the third consumer:
`webapp/js/polar.js` mirrors `notebook/polar.lua`, and both
`tests/polar.lua` and the Node suite read
`webapp/tests/fixtures/polar-parity.json`. The base fixture pins the resolved
rmax, projection, ring/theta labels, and bar sector for a small scene; the
`field_scene` fixture pins heatmap cell colours and radii, contour subdivision
and labels, colourbar geometry and compact tick text, and the field dimension
reservation. A change to one renderer either updates the shared contract
deliberately or fails a test.

## Markdown subset

The export renders the Markdown subset the notebook previews and edits:
ATX headings, fenced code blocks, unordered and ordered lists, blockquotes,
bold, inline code, `[label](url)` links (only `http`, `https`, `mailto`, and
relative links are emitted; `javascript:`/`data:` links degrade to text), and
wiki links as styled text with a `data-target` attribute. Raw HTML in Markdown
is escaped.

## Determinism

`Format.to_html` contains no clock or filesystem data, so exporting the same
notebook twice produces byte-identical HTML. The `?q=`/`?kind=` state is read
from the URL by the browser at open time and does not change the file bytes.
Figure numbering follows cell order. The JSON dump is omitted when the scene
IR contains non-JSON values such as functions.

## Headless export

From a source checkout the same exporter runs without LÖVR, which is useful for
CI and screenshot checks:

```sh
luajit tools/export.lua notebooks/demo.luanb /tmp/demo.html
luajit tools/export.lua notebooks/demo.luanb - > /tmp/demo.html
luajit tools/export.lua a.luanb /tmp/a.html b.luanb c.luanb  # backlinks
```

`INPUT.luanb` is read with the same decoder as the app, and `-` writes the HTML
to stdout. Extra arguments are backlink notebooks, so the closing backlinks
list matches what the command palette would emit. Output is deterministic for a
given input set.

## Tests and QA

```sh
luajit tests/run.lua
luajit tests/polar.lua    # shared geometry, live draw, export/live/browser parity
make test-webapp          # Node browser-renderer tests
./scripts/export-qa.sh    # needs chromium; screenshots stay in /tmp
./scripts/polar-qa.sh     # live app polar capture; needs lovr
./scripts/scene-qa.sh     # headless browser Canvas pixel check
```

The unit tests exercise heading anchors and duplicate slugs,
table-of-contents links, search-index normalization and escaping, figure
summaries/SVGs, polar axes and series, escaping, JSON truncation, tag filtering,
and timing sums. `tests/polar.lua` additionally checks the shared projection,
tick/label filters, bar sectors, heatmap-cell and contour geometry, colourbar
layout, the live draw-call shape, agreement between the live renderer and the
exported SVG, and the shared browser parity fixtures. `make test-webapp` checks
the JavaScript counterpart and its draw calls.
`scripts/export-qa.sh` builds a small notebook, exports it with
`tools/export.lua`, checks `?q=` and `?kind=` filtering through headless
Chromium, and captures light, dark, narrow, and filtered screenshots under a
scratch directory; it never commits them. `polar-qa.sh` runs a one-cell polar
notebook in the app and keeps a live screenshot under another scratch
directory, while `scene-qa.sh` renders the browser scene matrix in Chromium and
checks Canvas pixels.

For a rendered check from the app, export the demo notebook and open the
result:

```sh
LUANB_QA_CELL=9 lovr .       # run the polar cell, then export from the palette
chromium --headless --screenshot=/tmp/export.png file:///path/to/export.html
```

Search filtering can be checked without a visible browser:

```sh
chromium --headless --dump-dom \
  'file:///path/to/export.html?q=needle' | grep 'Showing'
```

The HTML feature is pure Lua; it does not add a runtime dependency or touch
the graphics path.
