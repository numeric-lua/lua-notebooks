# lua-notebooks 1.43.0

- static HTML export is now a navigable document: viewport/description
  metadata, dark-mode and print styles, unique heading anchors, a sticky table
  of contents, a figures index, per-cell permalinks, and a footer summary;
- code-cell scenes export as self-contained inline SVG figures for line,
  scatter, bar, histogram, `cube`, and `grid` scenes, with series/point
  captions and a collapsible JSON scene dump; static widget placeholders list
  the interactive widgets that were not exported;
- the static Markdown renderer handles fenced code, lists, quotes, safe links,
  and wiki links without injecting raw HTML;
- the tag index ignores tags inside fenced code, inline code, URL fragments,
  and hex colors, and its overlay exposes clickable per-notebook chips;
- the Neovim marker-deletion prompt previews every omitted cell before the
  undoable delete, and the status bar reports single-run and Run All timings;
- tests cover heading anchors, scene SVGs, HTML escaping, tag filtering,
  deletion previews, and timing sums; `make test` also runs the standalone
  Markdown-preview and type-completion suites;
- 1.42 Neovim deletion safety, optional per-cell timing, and the tag overlay
  are retained; no tag or package publish is part of this release commit.
