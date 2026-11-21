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
