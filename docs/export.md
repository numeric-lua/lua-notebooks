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

Each figure has a caption with the scene title, series kinds, series count,
and point count, plus a `<details>` block containing the JSON scene IR (capped
at 4,000 bytes). The SVG is a deterministic sketch of the scene, not a raster
of the live renderer; animated or custom extension surfaces need the desktop
app. Interactive widgets are not executed in the export; they are listed as
static placeholders.

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
./scripts/export-qa.sh   # needs chromium; screenshots stay in /tmp
```

The unit tests exercise heading anchors and duplicate slugs,
table-of-contents links, search-index normalization and escaping, figure
summaries/SVGs, polar axes and series, escaping, JSON truncation, tag filtering,
and timing sums. `scripts/export-qa.sh` builds a small notebook, exports it with
`tools/export.lua`, checks `?q=` and `?kind=` filtering through headless
Chromium, and captures light, dark, narrow, and filtered screenshots under a
scratch directory; it never commits them.

For a rendered check from the app, export the demo notebook and open the
result:

```sh
LUANB_QA_CELL=4 lovr .       # run a scene cell, then export from the palette
chromium --headless --screenshot=/tmp/export.png file:///path/to/export.html
```

Search filtering can be checked without a visible browser:

```sh
chromium --headless --dump-dom \
  'file:///path/to/export.html?q=needle' | grep 'Showing'
```

The HTML feature is pure Lua; it does not add a runtime dependency or touch
the graphics path.
