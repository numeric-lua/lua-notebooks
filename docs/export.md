# Static export

**Export notebook as HTML** in the command palette writes a single
self-contained file under the LÖVR save directory:

```text
exports/<notebook-name>.html
```

There are no external stylesheets, fonts, scripts, or image files. Open the
file directly from disk or serve it as a static page.

## Document shape

The exported document is meant to be read, linked, and printed, not just
dumped:

- `<meta name="viewport">`, description, color-scheme, generator, and Open
  Graph title/description elements;
- a header with the notebook title, kernel, and cell/figure/widget counts;
- a sticky `<nav class="toc">` table of contents built from Markdown headings,
  with GitHub-style unique anchors (`intro`, `intro-2`, …);
- a figures index that links to each exported scene;
- one `<section class="cell" id="cell-N">` per cell with a permalink;
- styled source, output, and error blocks;
- a backlinks list computed from `[[wiki links]]` across the open notebooks;
- a footer with cell, heading, and tag counts.

The stylesheet follows `prefers-color-scheme` for light/dark rendering and
includes a print stylesheet that hides navigation and page-break guards.

## Figures and widgets

Scene outputs become `<figure class="scene" id="figure-N">` elements:

| scene | static representation |
| --- | --- |
| `luaplotlib` `line` | SVG polyline, sampled to at most 800 points |
| `luaplotlib` `scatter` | SVG circles, sampled to at most 400 points |
| `luaplotlib` `bar` | SVG rectangles |
| `luaplotlib` `hist` | SVG rectangles from edges/counts |
| `"cube"` | inline isometric cube glyph |
| `"grid"` | inline perspective grid glyph |
| other table/extension scene | generic framed glyph |

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
notebook twice produces byte-identical HTML. Figure numbering follows cell
order. The JSON dump is omitted when the scene IR contains non-JSON values
such as functions.

## Tests and QA

```sh
luajit tests/run.lua
```

This exercises heading anchors and duplicate slugs, table-of-contents links,
figure summaries/SVGs, escaping, JSON truncation, tag filtering, and timing
sums. For a rendered check, export the demo notebook and open the result:

```sh
LUANB_QA_CELL=4 lovr .       # run a scene cell, then export from the palette
chromium --headless --screenshot=/tmp/export.png file:///path/to/export.html
```

The HTML feature is pure Lua; it does not add a runtime dependency or touch
the graphics path.
