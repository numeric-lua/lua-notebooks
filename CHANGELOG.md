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

Added `tests/workflow.lua` coverage for paste, run-above dispatch, and filetree
keyboard navigation; `tests/run.lua` covers filetree sorting and duplicate-cell undo, the workflow
smoke covers run-above execution, and the browser Markdown suite covers
code-block badges/copy markup.
The filetree overlay QA screenshot and `LUANB_SMOKE_WORKFLOW` are green. Neovim
behavior, the static export, and committed visual baselines are unchanged.
