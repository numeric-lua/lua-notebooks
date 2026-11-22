# lua-notebooks status

## Working

- LÖVR notebook shell with tabs, scrolling, 3D viewports, save/load.
- LuaJIT thread kernels and an experimental POSIX process-kernel backend.
- Process CPU/memory limits and timeout recovery.
- luaplotlib scene rendering, including live Cartesian and polar
  line/scatter/bar/hist scenes, polar heatmaps with colourbars and bounded
  block sampling for large fields, polar contour isolines, and polar quiver
  arrows with shared scale/pivot/decimation geometry and export attributes.
- Browser front-end with local Canvas rendering for Cartesian
  line/scatter/bar/hist and polar line/scatter/bar/heatmap/contour/quiver
  scenes, shared polar parity fixtures, and a headless Chromium pixel check.
- Extension manifests, discovery, hot reload, browser, local user extensions,
  and a restricted Lua environment.
- Kernel widgets, editable multiline text, callbacks, persistence, and live
  shader widgets (Star Nest preset).
- Syntax highlighting, static diagnostics, completion, hover, go-to-definition,
  and workspace rename.
- Hierarchical notebook filetree with create/delete/rename/folder actions.
- Vim mode (default on): insert/normal, cell/character visual, registers,
  yank/paste, undo, search, command line, literal/pattern substitution.
- Inline and display math: symbols, fractions, radicals, simple matrices.
- Collapsible markdown headings and heading outline.
- Command palette, tag-index overlay with per-notebook chips, optional
  per-cell execution timing, shortcut help, zip package, local install,
  desktop entry, and LuaRocks package/launcher.
- Confirmed, undoable cell deletion when notebook-wide Neovim markers omit a
  cell; the prompt previews every omitted cell.
- Navigable static HTML export with metadata, heading anchors/table of
  contents, a figures index, inline SVG scene previews (including polar
  scenes), full-text search and a cell-kind filter, scene JSON, and printable
  light/dark styling.
- Pure test suite and GitHub Actions CI.
- Manual physical-input and visual smoke scripts.

## Not done

- True TeX/MathJax-quality math layout and fonts.
- Semantic type/scope analysis beyond the current local LSP helpers.
- OS sandboxing is available on Linux through bubblewrap; macOS/Windows use
  the restricted Lua-environment fallback.
- Full Vim semantics: undo tree, regex parity, text objects, macros.
- Broader live visual coverage beyond QA cells 4/6/7, the polar QA fixture, and
  the browser scene matrix.
- Static export cannot run widgets or reproduce animated/custom extension
  surfaces; it emits placeholders and scene sketches.

## Verify

```sh
make test
make test-webapp           # Node scene/model tests, no packages
./scripts/input-smoke.sh   # needs a seat and /dev/uinput
./scripts/visual-smoke.sh  # needs a display
./scripts/scene-qa.sh      # needs chromium
luarocks make lua-notebooks-1.49.0-1.rockspec --tree=/tmp/luanb-rocks
```
