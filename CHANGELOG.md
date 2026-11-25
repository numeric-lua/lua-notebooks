# Changelog

## Unreleased

- paste clipboard text into the selected code or Markdown cell with **Ctrl+V**
  or the **Paste into selected cell** palette action; pastes use the normal
  undo history and report the inserted character count;
- run the selected cell and every code cell above it with **Ctrl+Alt+Up** or
  the **Run selected cell and above** palette action, executing in source order
  so earlier cells see the state they expect;
- sort the **F2** notebook filetree by **A→Z**, **Z→A**, or **Recent** via the
  **Sort** button or **Cycle filetree sort** palette action, persisting the
  choice in `tree_sort.txt`;
- navigate the filetree from the keyboard: Up/Down move the highlighted row,
  Enter opens a notebook or expands a folder, and filtering resets the
  selection to the first match;
- browser Markdown fenced code blocks now show a language badge and a **Copy**
  control that copies the block without any badge text; unknown languages fall
  back to `text`.
- save every dirty notebook with **Ctrl+Alt+S** or **Save all notebooks**, with
  a per-run saved/failed count;
- restart every notebook kernel with **Ctrl+Alt+K** or **Restart all kernels**,
  clearing running flags and pending requests for all tabs;
- expand or collapse every long output as one undoable edit with the
  **Expand all long outputs** and **Collapse all long outputs** palette actions;
- browser Markdown previews now give headings deterministic cell-scoped IDs
  and hover/focus `#` permalinks, and render single-line or fenced `$$...$$`
  math as centered display blocks;
- toggle a `--` comment on the current code line with **Ctrl+/**;
- move the current line up or down with **Alt+Shift+Up** / **Alt+Shift+Down**;
- duplicate the current line with **Ctrl+Shift+D**;
- indent or outdent the current line with **Ctrl+]** / **Ctrl+[**;
- jump to a numbered line in the selected cell with **Ctrl+Alt+L** or the
  **Go to line in cell** palette prompt;
- move the caret by word with **Ctrl+Left** / **Ctrl+Right**;
- delete the previous word with **Ctrl+Backspace**;
- delete the next word with **Ctrl+Delete**;
- jump to the start or end of the cell with **Ctrl+Home** / **Ctrl+End**;
- join the current line with the next with **Ctrl+J**.

Tests: `tests/workflow.lua` covers paste, run-above dispatch, save/restart-all
dispatch, filetree keyboard navigation, and output-fold dispatch; `tests/run.lua`
covers filetree sorting, bulk output folding, duplicate-cell undo, line editing
(move/duplicate/comment/indent/go-to-line), word movement/deletion, and line
joining; the browser Markdown suite
covers code-block badges/copy markup, heading anchor uniqueness, permalinks, and
display math. The filetree overlay QA screenshot and
`LUANB_SMOKE_WORKFLOW` (including save-all, restart-all, run-above, paste, and
output folding) are green. Neovim behavior, the static export, and committed
visual baselines are unchanged.
