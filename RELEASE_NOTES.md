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
