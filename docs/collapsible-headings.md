# Collapsible headings

Markdown cells whose source starts with `#`, `##`, etc. are headings.

- A heading cell shows a `▾`/`▸` marker.
- Clicking the heading toggles its collapsed state.
- A collapsed heading hides following cells until the next heading of the same
  or higher level.
- The state is stored as `collapsed` in the `.luanb` cell.
- Heading navigation and folding are notebook-only; the kernel is unaffected.

This is intentionally simpler than JupyterLab’s outline UI; there is no separate
outline sidebar yet.
