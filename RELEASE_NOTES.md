# lua-notebooks 1.44.0

- add reader-facing full-text search and an All/Code/Markdown/Figures filter to
  the static HTML export, with `/` focus, Escape clearing, table-of-contents
  filtering, `?q=`/`?kind=` link state, and a no-JavaScript fallback;
- preview luaplotlib polar scenes in the export: circular frame, r rings,
  theta spokes, line/scatter/bar series, `theta_zero`/`theta_direction`, and
  clamped `rmax`, with escaped long-label handling;
- add `tools/export.lua` for LÖVR-free HTML export in CI/QA and
  `scripts/export-qa.sh` for headless Chromium search checks plus
  light/dark/narrow screenshots;
- extend tests and export docs for search, polar previews, and headless QA.

No new runtime dependencies. The inline Neovim path and the visual pixel
baselines are unchanged.
