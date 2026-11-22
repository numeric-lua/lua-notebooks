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
