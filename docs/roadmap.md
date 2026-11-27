# lua-notebooks status

## Working

- LÖVR notebook shell with tabs, scrolling, 3D viewports, save/load.
- LuaJIT thread kernels and an experimental POSIX process-kernel backend.
- Process CPU/memory limits and timeout recovery.
- luaplotlib scene rendering, including live Cartesian and polar
  line/scatter/bar/hist scenes, polar heatmaps with colourbars and bounded
  block sampling for large fields, polar contour isolines, polar quiver
  arrows with shared scale/pivot/decimation geometry, and polar streamplot
  paths with mid-line arrow heads, circular-frame clipping, dashed/dotted/`none`
  strokes, and source/visible export attributes.
- Browser front-end with local Canvas rendering for Cartesian
  line/scatter/bar/hist and polar
  line/scatter/bar/heatmap/contour/quiver/streamplot scenes, shared polar
  parity fixtures, and a headless Chromium pixel check.
- Extension manifests, discovery, hot reload, browser, local user extensions,
  and a restricted Lua environment.
- Kernel widgets, editable multiline text, callbacks, persistence, live
  shader widgets (Star Nest preset), and expandable long text output.
- Syntax highlighting, static diagnostics, completion, hover, go-to-definition,
  workspace rename, literal or Lua-pattern find/replace with case and
  whole-word options, a current-cell scope, and a cross-notebook search
  overlay with per-tab result jumps, paged result rows, and cell-kind filters.
  Command palette, tag index, heading outline, and filetree rows also page
  cleanly, and recently used palette commands float to the top. Execution
  includes Shift+Enter run-next, Alt+Enter run-and-insert, clear-and-rerun,
  restart-and-clear, and a stoppable run-all queue. Notebook identity covers
  named creation, folder moves, duplication, title renaming, and revealing the
  active file through expanded ancestors. Markdown editing includes bold,
  italic, inline code, highlight, strikethrough, blockquote, list, heading, and
  link actions.
- GitHub-style Markdown pipe tables, nested lists, italic emphasis, grouped
  blockquotes, highlight, bare-URL autolinks, backslash escapes, and numbered
  footnotes with endnote backlinks across the preview, static export, and
  browser front-end.
- Notebook workflow commands: restart-and-run-all, run selected-and-below,
  copy cell source/output, paste the clipboard, clear the selected output,
  reopen the last closed tab, close other clean tabs, go to a cell number,
  duplicate a cell, run selected-and-above, save all notebooks, restart all
  kernels, expand/collapse all long outputs, move the selected cell with
  Alt+Up/Down, heading navigation, collapse/expand all headings, and a
  type-to-filter outline. Line editing covers comment toggle, line move,
  duplicate, indent/outdent, word movement/deletion, line joining, cell
  bounds, and go-to-line.
- Clickable Markdown task-list markers in the live preview and nested
  blockquotes and GitHub-style callouts across the preview, static export,
  and browser front-end; clickable browser task checkboxes, definition lists
  across all three Markdown surfaces, browser code-block badges/copy controls,
  clickable preview wiki links, browser heading anchor permalinks and display
  math blocks, and a filterable tag index.
- Close-notebook tabs with an unsaved-changes guard; kernels are keyed by
  notebook object so other tabs keep their globals.
- Filterable, sortable, keyboard-navigable hierarchical notebook filetree with
  folder-aware notebook/subfolder creation, folder rename, empty-folder delete,
  expand/collapse-all commands, Left/Right fold toggles, and Home/End row
  jumps.
- Vim mode (default on): insert/normal, cell/character visual, registers,
  yank/paste, undo, search, command line, literal/pattern substitution.
- Inline and display math: symbols, fractions, radicals, simple matrices.
- Collapsible markdown headings and heading outline.
- Command palette, tag-index overlay with per-notebook chips, optional
  per-cell execution timing, a notebook-statistics overlay, shortcut help, zip
  package, local install, desktop entry, and LuaRocks package/launcher.
- Confirmed, undoable cell deletion when notebook-wide Neovim markers omit a
  cell; the prompt previews every omitted cell.
- Navigable static HTML export with metadata, heading anchors/permalinks and
  table of contents, a figures index, inline SVG scene previews (including
  polar scenes), Markdown rules/strikethrough/ordered-list starts, full-text
  search and a cell-kind filter, scene JSON, and printable light/dark styling.
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
LUANB_SMOKE_WORKFLOW=1 lovr . # shortcut and restart/run-all smoke
./scripts/input-smoke.sh   # needs a seat and /dev/uinput
./scripts/visual-smoke.sh  # needs a display
./scripts/scene-qa.sh      # needs chromium
luarocks make lua-notebooks-1.59.0-1.rockspec --tree=/tmp/luanb-rocks
```
