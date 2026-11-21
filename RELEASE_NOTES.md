# lua-notebooks 1.42.0

- notebook-wide Neovim saves that omit a `-- %% cell N` marker now pause for
  explicit Enter/y confirmation; the deletion is undoable and Esc/n keeps the
  buffer;
- optional per-cell execution timing (Ctrl+Shift+E), hidden by default so cell
  layout and committed visual baselines stay unchanged;
- Ctrl+T tag index overlay with per-tag counts across open notebooks and
  click-through to a notebook-wide tag search;
- tests and docs cover marker deletion, kernel timings, and tag aggregation;
- 1.41 link graph and styled HTML export retained.
