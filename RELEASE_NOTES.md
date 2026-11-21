# lua-notebooks 1.45.0

- render luaplotlib polar scenes in the live notebook viewport: circular
  frame, r rings, theta spokes, line/scatter/bar series,
  `theta_zero`/`theta_direction`, clamped `rmax`, short tick labels, and a
  theme-aware surface;
- share polar geometry through `notebook/polar.lua` so the live renderer and
  the static HTML export agree on rmax fallback, projection, tick filtering,
  sampling caps, long-label omission, and wide/negative-radius bar wedges;
- add a polar scene to the welcome notebook and give polar cells a taller
  scene area;
- add `tests/polar.lua` for shared geometry, live draw calls, and export/live
  parity, `LUANB_SMOKE_POLAR=1` for a repeatable app smoke, and
  `scripts/polar-qa.sh` for a live, non-blank screenshot check;
- document the shared polar backend and parity contract.

No new runtime dependencies. The inline Neovim path and the committed visual
pixel baselines are unchanged.
