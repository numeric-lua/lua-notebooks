# lua-notebooks 1.58.0

- add **Ctrl+Alt+T** and a palette action to reopen the most recently closed
  notebook tab, restoring the in-memory notebook, its dirty state, and a fresh
  kernel;
- make the **Ctrl+T** tag index filterable: type a case-insensitive substring,
  see matched/total tag counts, move the highlight with Up/Down, and open the
  selected tag with Enter;
- add **Ctrl+Alt+X** and a palette action to clear the selected cell's output,
  scene, widgets, and error, refusing while that cell is running;
- make rendered wiki links clickable in the live Markdown preview, switching to
  the matching notebook tab;
- render GitHub-style callouts (`> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`,
  `[!WARNING]`, `[!CAUTION]`) in the live preview, static HTML export, and
  browser front-end, with normalized titles, shared body formatting, and
  unknown markers staying ordinary blockquotes;
- extend `tests/workflow.lua`, `tests/run.lua`, `tests/markdown.lua`, and the
  browser Markdown suite; expand `LUANB_SMOKE_WORKFLOW` to cover tag filtering,
  wiki-link clicks, and selected-output clearing; extend `LUANB_SMOKE_CLOSE`
  to reopen the closed tab; add callout and nested-quote DOM checks to
  `scripts/export-qa.sh`; update the welcome notebooks and document the new
  behavior in the README, `docs/export.md`, `docs/web.md`, `docs/roadmap.md`,
  and `webapp/README.md`.

No new runtime dependencies. The Neovim path, kernel protocol, and committed
visual pixel baselines are unchanged. `make test`, `make test-nvim`,
`make test-webapp`, `LUANB_SMOKE_WORKFLOW=1 lovr .`, `LUANB_SMOKE_CLOSE=1 lovr .`,
the pixel baseline check, `scripts/export-qa.sh`, and `scripts/scene-qa.sh`
pass. This release is tagged `v1.58.0`.

# lua-notebooks 1.57.0

- make Markdown task-list markers clickable in the live preview: clicking
  `[x]`/`[ ]` toggles only that marker in the cell source as one undoable edit,
  preserving indentation and the rest of the line; the static export and
  browser keep their read-only disabled checkboxes;
- add **Ctrl+Alt+C** and a palette action to copy the selected cell's captured
  text output, falling back to its error text and refusing scene-only cells;
- add **Ctrl+Alt+Enter** and a palette action to run the selected cell and
  every code cell below it without rerunning earlier cells;
- make the **F11** outline filterable: type a case-insensitive substring, see
  the matched/total count, move the highlight with Up/Down, and jump with Enter
  or a click;
- render nested Markdown blockquotes in the live preview (`│` indentation), the
  static HTML export, and the browser front-end, while depth-one quotes keep
  their existing one-paragraph-per-line layout;
- extend `tests/workflow.lua`, `tests/run.lua`, `tests/markdown.lua`, and the
  browser Markdown suite; expand `LUANB_SMOKE_WORKFLOW` to cover task clicks,
  outline filtering, output copy, and run-below execution; add nested-quote DOM
  checks to `scripts/export-qa.sh`; update the welcome notebooks and document
  the new behavior in the README, `docs/export.md`, `docs/web.md`,
  `docs/roadmap.md`, and `webapp/README.md`.

No new runtime dependencies. The Neovim path, kernel protocol, and committed
visual pixel baselines are unchanged. `make test`, `make test-nvim`,
`make test-webapp`, `LUANB_SMOKE_WORKFLOW=1 lovr .`, the pixel baseline check,
`scripts/export-qa.sh`, and `scripts/scene-qa.sh` pass. This release is tagged
`v1.57.0`.

# lua-notebooks 1.56.0

- add **Ctrl+Shift+F5** and a command-palette action to restart the current
  kernel and immediately run every code cell, so the first cell sees a fresh
  global state;
- add **Ctrl+Shift+C** and a palette action to copy the selected cell source
  exactly, without writing to the notebook or marking it dirty;
- move the selected cell with **Alt+Up** / **Alt+Down** (the existing palette
  move actions now show the shortcuts);
- add **Ctrl+Shift+Up** / **Ctrl+Shift+Down** heading navigation plus
  **Collapse all headings** and **Expand all headings** palette actions, with
  the fold change stored as one undoable edit;
- render Markdown footnotes across the live preview, static HTML export, and
  browser front-end: `[^label]` references, single-line `[^label]: text`
  definitions, first-reference numbering, an endnotes section with per-note
  backlinks, literal handling inside code and for undefined/escaped
  references, and light/dark/print styles;
- add `tests/workflow.lua`, a `LUANB_SMOKE_WORKFLOW` LÖVR smoke that exercises
  the shortcut dispatch and a real restart-run-all cycle, footnote unit and
  browser tests, footnote DOM checks in `scripts/export-qa.sh`, a footnote demo
  cell in the desktop and browser welcome notebooks, and documentation in the
  README, `docs/export.md`, `docs/web.md`, `docs/roadmap.md`, and
  `webapp/README.md`.

No new runtime dependencies. The Neovim path, kernel protocol, and committed
visual pixel baselines are unchanged. `make test`, `make test-nvim`,
`make test-webapp`, `LUANB_SMOKE_WORKFLOW=1 lovr .`, the pixel baseline check,
`scripts/export-qa.sh`, and `scripts/scene-qa.sh` pass. This release is tagged
`v1.56.0`.

# lua-notebooks 1.55.0

- add a type-to-filter field to the **F2** notebook filetree: case-insensitive
  filename matching searches collapsed folders, keeps ancestor directories,
  shows a match count and empty state, opens the first match with Enter, and
  leaves create/rename/delete actions available on the filtered rows;
- add **Alt+L** current-cell scope to notebook find and replace: result rows
  keep their real cell numbers, output rows stay searchable for find, replace
  counts and applies only in the selected cell, and the overlay header reports
  `current cell` versus `notebook`;
- render Markdown highlight (`==text==`) as a styled `<mark>` in the static
  export and browser front-end and as plain text in the live preview, with
  light/dark/print styles;
- autolink bare `http(s)://` URLs in the static export and browser front-end
  without touching inline code, explicit link destinations, or explicit link
  labels; trim trailing sentence punctuation and unbalanced closing parentheses
  while preserving balanced parentheses and HTML entities;
- support backslash escapes for Markdown punctuation (`\*`, `\_`, an escaped
  backtick, brackets, parentheses, headings, list markers, emphasis, highlight,
  pipes, and `\\`) across the live preview, static export, and browser so
  escaped punctuation never triggers formatting;
- add an inline-details demo cell and browser welcome text, extend
  `tests/markdown.lua`, `tests/run.lua`, and the Node Markdown suite, and add
  highlight/autolink/escape DOM checks to `scripts/export-qa.sh`; document the
  filetree filter, cell-scoped search, and inline Markdown behavior in the
  README, `docs/export.md`, `docs/roadmap.md`, and `webapp/README.md`.

No new runtime dependencies. The committed visual pixel baselines, Neovim path,
and kernel protocol are unchanged. `make test`, `make test-nvim`,
`make test-webapp`, the pixel baseline check, `scripts/export-qa.sh`,
`scripts/scene-qa.sh`, and the LÖVR smoke suite pass. This release is tagged
`v1.55.0`.

# lua-notebooks 1.54.0

- render GitHub-style Markdown pipe tables in the live preview, the static HTML
  export, and the browser front-end: strip optional outer pipes, honor
  `:---`/`:---:`/`---:` alignment, escape cell content, keep tables inside
  fenced code as code, and style exported and browser tables for light/dark and
  print;
- render nested unordered, ordered, and task lists in all three Markdown
  renderers, preserving indentation depth, mixed list kinds, ordered-list start
  numbers, disabled task checkboxes, and the existing preview bullet markers;
- align inline emphasis and blockquotes across the preview/export/browser:
  italic `*text*`/`_text_`, bold `**text**`/`__text__`, strikethrough, inline
  code precedence, and one grouped `<blockquote>` for consecutive `>` lines;
- add **Alt+R** Lua-pattern search and replace to the find, cross-notebook
  search, and replace overlays: numbered captures (`%1`–`%9`, `%0`, `%%`) in
  replacements, case/whole-word combinations, malformed-pattern reporting
  instead of crashes, and skipped zero-length matches;
- add **Ctrl+W** and a palette action to close the current notebook tab, with an
  unsaved-changes prompt (**Enter/Y** discard, **S** save and close,
  **Escape/N** cancel), stable kernel ids keyed by notebook object, and
  supervisor stop support so closing one tab keeps every remaining kernel and
  its globals alive;
- add table, nested-list, emphasis, and pattern-search demo cells after the
  existing welcome-notebook cells; extend `scripts/export-qa.sh` with table,
  nesting, and italic DOM checks; add `LUANB_SMOKE_CLOSE`; and document the new
  behavior in the README, `docs/export.md`, `docs/roadmap.md`, `docs/web.md`,
  and `webapp/README.md`.

No new runtime dependencies. The committed visual pixel baselines, Neovim
path, and kernel protocol are unchanged. `make test`, `make test-nvim`,
`make test-webapp`, the pixel baseline check, `scripts/export-qa.sh`,
`scripts/scene-qa.sh`, and the close-tab LÖVR smoke pass. This release is
tagged `v1.54.0`.

# lua-notebooks 1.53.0

- add **Ctrl+Shift+F** cross-notebook search: match every open notebook at
  once, group rows by notebook title and cell number, show the total
  occurrence count across tabs, honor the existing case-sensitive and
  whole-word options, and jump to the owning tab, cell, and cursor with Enter
  or a click; expose the same action from the command palette and shortcut
  help, and add `LUANB_SMOKE_GLOBAL_FIND`;
- render Markdown thematic breaks (`---`, `***`, `___`) in the live preview
  and static HTML export, with a print-safe rule style and preview/export/browser
  tests;
- render Markdown strikethrough (`~~text~~`) in the live preview and static
  HTML export, matching the browser front-end, with a muted `<del>` style and
  tests;
- preserve ordered-list start numbers in the static export and browser
  front-end (`3.` / `3)` produce `<ol start="3">`), keep the live preview
  source numbering, and accept both `.` and `)` list markers;
- add a hover/focus `#` permalink to every rendered heading in the static
  export, pointing at the same deterministic anchor used by the table of
  contents, with printable styling and DOM/export-QA coverage;
- document the cross-notebook search shortcut and overlay, heading permalinks,
  Markdown rules/strikethrough/ordered-list starts, the new smoke hook, and the
  expanded `scripts/export-qa.sh` checks in the README, `docs/export.md`,
  `docs/roadmap.md`, and `webapp/README.md`.

No new runtime dependencies. The desktop kernel, Neovim path, and committed
visual pixel baselines are unchanged. `make test`, `make test-nvim`,
`make test-webapp`, the pixel baseline check, `scripts/export-qa.sh`,
`scripts/scene-qa.sh`, and the LÖVR smoke suite pass. This release is tagged
`v1.53.0`.

# lua-notebooks 1.52.0

- add case-sensitive and whole-word options to notebook find and replace
  (`Alt+C` / `Alt+W`), show total occurrence counts separately from the
  40-row result list, preview the replacement count, and share literal
  matching through `notebook/search.lua`;
- render Markdown task lists (`- [x]` / `- [ ]`) as font-safe `[x]`/`[ ]`
  preview markers and as disabled HTML checkboxes in the static export and
  browser front-end, with a checklist demo cell after the visual-baseline
  cells;
- give static HTML code cells and fenced blocks a language badge, CSS line
  numbers, and a JavaScript **Copy** control that copies the source without
  the numbers; the control is hidden when JavaScript is unavailable;
- add a `Ctrl+Shift+I` notebook-statistics overlay and palette command showing
  cells, source lines by kind, prose words, headings, wiki links, tags, text
  outputs, figures, widgets, errors, timed execution, and kernel;
- expand/collapse long text output with a line-count header, persisted
  `output_expanded` cell flag, `Ctrl+Shift+O`, and a palette action; short
  output and the committed visual-baseline cells keep their existing layout;
- select smoke-test cells by demo markers instead of stale fixed indices, and
  stabilize the existing Neovim RPC/session tests on current Neovim
  (`noswapfile` and tight UI pumps); no Neovim product behavior changed;
- document the search options, checklist preview/export behavior, code-copy
  controls, statistics overlay, output expansion, and new smoke/QA flags.

No new runtime dependencies. The Neovim path and committed visual pixel
baselines are unchanged. This release is tagged `v1.52.0`.

# lua-notebooks 1.51.0

- clip luaplotlib polar streamplot polylines and mid-line arrow heads to the
  circular frame in the live viewport and the static HTML export, matching the
  browser's existing Canvas clip through one shared circle-cut geometry in
  `notebook/polar.lua` and `webapp/js/polar.js`; a crossing line is cut at the
  circle instead of being clamped along the rim, a line that leaves and
  re-enters becomes several visible runs, a rim arrow head becomes a clipped
  polygon, and a fully outside arrow is omitted;
- export one `scene-polar-streamline-path` per visible run, a circular
  `clipPath` around the streamplot group so stroke caps cannot spill past the
  frame, and `data-visible-lines`/`data-visible-points`/`data-visible-runs`
  plus per-line `data-runs`/`data-clipped` counters alongside the existing
  source counts;
- collect streamplot `style.linestyle` (`solid`, `dashed`, `dotted`, `none`),
  `arrow_fraction`, per-line `closed`, and the group `closed_lines` count;
  draw dashes through the shared live dash splitter, SVG `stroke-dasharray`,
  and Canvas `setLineDash`, and keep mid-line heads when `linestyle = "none"`,
  matching luaplotlib;
- add the `streamplot_clip_scene` cross-renderer fixture read by
  `tests/polar.lua` and the Node suite, a `polar-streamplot-clip` case in the
  headless Chromium scene matrix, and clipped dashed streamplot checks in
  `scripts/export-qa.sh` and `scripts/polar-qa.sh`, including visible
  run/point/arrow counts;
- add a clipped dashed streamplot demo cell to the desktop and browser welcome
  notebooks after the existing cells, leaving visual-baseline cells 4/6/7
  unchanged;
- document frame clipping, visible/source counters, line styles, the clipPath,
  and the new fixture in the README, `docs/export.md`, `docs/web.md`,
  `docs/architecture.md`, `docs/roadmap.md`, and `webapp/README.md`.

No new runtime dependencies. The Neovim path and committed visual pixel
baselines are unchanged. No tag or package publish is part of this release
preparation.

# lua-notebooks 1.50.0

- render luaplotlib polar streamplot scenes in the live viewport, the static
  HTML export, and the browser front end, projecting the integrated
  `(theta, r)` polylines and rebuilding the mid-line arrow heads from the
  exported screen-space angle;
- collect the streamplot IR in `notebook/polar.lua` with grid dimensions,
  resolved and automatic `step` metadata, `density`, `max_steps`/`max_lines`/
  `max_points`, `periodic`, `truncated`, `arrows`, `head`, `linewidth`, alpha,
  and polyline/arrow counters, filtering malformed points and lines
  consistently across renderers;
- export `scene-polar-streamplot` groups with grid, step, cap, periodicity, and
  arrow data attributes, plus `scene-polar-streamline` groups carrying
  `scene-polar-streamline-path` polylines and `scene-polar-stream-arrow`
  polygons in series order; captions count integrated polyline points rather
  than value-grid cells;
- add the `streamplot_scene` cross-renderer fixture read by `tests/polar.lua`
  and the Node suite, a `polar-streamplot` case in the headless Chromium scene
  matrix, and streamline/path count checks in the live `polar-qa.sh` and static
  `export-qa.sh` paths;
- add polar streamplot demo cells to the desktop and browser welcome notebooks
  after the existing cells, leaving the visual-baseline cells 4/6/7 unchanged;
- document the streamplot IR, export attributes, Canvas clipping, step and
  periodicity metadata, parity fixture, and QA coverage in the README,
  `docs/export.md`, `docs/web.md`, `docs/architecture.md`, `docs/roadmap.md`,
  and `webapp/README.md`.

No new runtime dependencies. The Neovim path and committed visual pixel
baselines are unchanged. No tag or package publish is part of this release
preparation.

# lua-notebooks 1.49.0

- render luaplotlib polar quiver scenes in the live viewport, the static HTML
  export, and the browser front end, with shared projection of the local
  tangential (`u`) and radial (`v`) components through
  `theta_zero`/`theta_direction`;
- resolve explicit or automatic glyph scaling, `pivot` (tail/middle/tip),
  `normalize`, `head`, `linewidth`, alpha, and deterministic `max_arrows`
  decimation in `notebook/polar.lua`, so a kernel-built scene and an exported
  luaplotlib scene draw the same arrows;
- export `scene-polar-quiver` groups with count/drawn/stride/scale/pivot data
  attributes and `scene-polar-quiver-arrow` groups carrying index, magnitude,
  theta, r, and angle, with shaft and head children in the series order;
- add the `quiver_scene` cross-renderer fixture read by `tests/polar.lua` and
  the Node suite, a `polar-quiver` case in the headless Chromium scene matrix,
  and quiver count checks in the live `polar-qa.sh` and static `export-qa.sh`
  paths;
- add polar quiver demo cells to the desktop and browser welcome notebooks
  after the existing cells, leaving the visual-baseline cells 4/6/7 unchanged;
- document the quiver IR, export attributes, Canvas clipping, scale/pivot
  rules, decimation, and parity fixtures in the README, `docs/export.md`,
  `docs/web.md`, `docs/architecture.md`, `docs/roadmap.md`, and
  `webapp/README.md`.

No new runtime dependencies. The Neovim path and committed visual pixel
baselines are unchanged.

# lua-notebooks 1.48.0

- sample polar heatmap fields above 4096 matrix cells into covering blocks in
  the live viewport, the static HTML export, and the browser renderer; each
  block spans the source rows and columns it replaces, so downsampling never
  leaves gaps in the annulus;
- keep `vmin`/`vmax` normalization tied to the full field: an explicit range
  is used unchanged and a missing range scans every source cell before
  sampling; captions continue to count source matrix values, not painted
  blocks;
- record the source grid and sampling strides on the exported heatmap group
  (`data-rows`, `data-cols`, `data-row-step`, `data-col-step`,
  `data-sampled`) and per-block spans on sampled cells;
- add the `large_field_scene` cross-renderer fixture, a 65x65 sampling
  contract in `tests/polar.lua` and the Node suite, and a
  `large-polar-field` case in the headless Chromium scene matrix;
- add large-field demo cells to the desktop and browser welcome notebooks, and
  a 512x512 collect/project benchmark to `make bench`;
- add a visual-baseline guard that pins the demo cells 4/6/7 scenes and checks
  the committed baseline images exist and are intact;
- document the 4096-cell cap, block coverage, export attributes, and parity
  fixtures in the README, `docs/export.md`, `docs/web.md`,
  `docs/architecture.md`, `docs/roadmap.md`, and `webapp/README.md`.

No new runtime dependencies. The Neovim path and committed visual pixel
baselines are unchanged.

# lua-notebooks 1.47.0

- render luaplotlib polar heatmaps in the live viewport, the static HTML
  export, and the browser front-end: shared viridis-like palette,
  annular/pie cells, full-turn ring splitting into convex wedges,
  non-finite-cell fallbacks, and a stepped vertical colourbar with compact
  ticks and an optional rotated title;
- render polar contour isolines in all three consumers: data-space
  marching-squares segments subdivided in angular/radial space, dashed and
  dotted styles, and per-level labels placed on the farthest segment and
  clamped inside the frame;
- reserve the colourbar column in the shared frame layout, include field
  extents in the observed `rmax`, and keep colourbar geometry/labels
  deterministic across Lua and JavaScript;
- extend `notebook/polar.lua`, `ui/plot.lua`, `notebook/format.lua`, and
  `webapp/js/polar.js` with the shared field contract, pinned by a second
  `field_scene` fixture in `webapp/tests/fixtures/polar-parity.json` read by
  both `tests/polar.lua` and the Node suite;
- add polar heatmap/contour/colourbar cells to the desktop demo and browser
  welcome notebooks;
- extend `make test-webapp` / `make qa-webapp` with the field fixture and add
  heatmap, contour, and colourbar rendering to the live `polar-qa.sh` capture;
- document the field contract in the README, `docs/export.md`, `docs/web.md`,
  `docs/architecture.md`, `docs/roadmap.md`, and `webapp/README.md`.

No new runtime dependencies. The Neovim path and committed visual pixel
baselines are unchanged.

# lua-notebooks 1.46.0

- render luaplotlib polar scenes in the browser webapp: circular frame, r
  rings, theta spokes, line/scatter/bar series, `theta_zero`/
  `theta_direction`, explicit or observed `rmax`, clamped radii, short tick
  labels, and wide or negative-radius bar wedges;
- bring the browser Cartesian renderer to parity with the desktop and export
  paths: histogram series, categorical x ticks, explicit bar widths,
  bar/histogram extents in the data bounds, non-finite filtering, and the same
  800/400 line/scatter sampling caps;
- add a polar rose cell to the webapp welcome notebook;
- add `webapp/js/polar.js` as the JavaScript counterpart of
  `notebook/polar.lua`, with `webapp/tests/fixtures/polar-parity.json` read by
  both `tests/polar.lua` and the Node suite so rmax, projection, ticks, labels,
  and bar sectors cannot drift silently;
- add `make test-webapp` coverage for polar geometry, Cartesian parity, draw
  calls, and malformed scenes, plus `make qa-webapp` /
  `scripts/scene-qa.sh`, a headless Chromium Canvas pixel check for the whole
  scene fixture matrix;
- document the browser renderer, its shared parity contract, and the new QA
  commands.

No new runtime dependencies. The desktop viewport, Neovim path, and committed
visual pixel baselines are unchanged.
