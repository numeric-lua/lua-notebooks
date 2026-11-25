-- Workflow shortcut wiring.  LÖVR is stubbed so the keyboard dispatch and
-- command-palette routing can be checked without opening a window.
local root = (arg and arg[0] or "tests/workflow.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

lovr = {
  system = {
    isKeyDown = function() return false end,
    getClipboardText = function() return "pasted" end,
  },
}

local Notebook = require("notebook.model")
local UI = require("ui.notebook")

local notebook = Notebook.new({ cells = {
  { kind = "markdown", source = "# One\n\nSee [[Two]]" },
  { kind = "code", source = "print(1)" },
  { kind = "markdown", source = "## Two" },
  { kind = "markdown", source = "- [ ] task\n\nTags: #alpha #beta" },
} })
local calls = {
  move = 0, heading = 0, copy = 0, restart = 0, collapse = 0,
  copy_output = 0, run_below = 0, clear_output = 0, reopen = 0,
  open_title = 0, duplicate = 0, close_others = 0, run_above = 0,
  open_path = 0, cycle_sort = 0, save_all = 0, restart_all = 0,
  expand_outputs = 0,
}
local app = {
  notebooks = { notebook },
  active = 1,
  vim_mode = false,
  show_nvim = false,
  status = "",
  notebook = function(self) return self.notebooks[self.active] end,
  move_cell = function(self, delta) calls.move = calls.move + delta end,
  goto_heading = function(self, delta)
    calls.heading = calls.heading + delta
  end,
  copy_cell_source = function(self) calls.copy = calls.copy + 1 end,
  copy_cell_output = function(self) calls.copy_output = calls.copy_output + 1 end,
  run_all_below = function(self) calls.run_below = calls.run_below + 1 end,
  run_all_above = function(self) calls.run_above = calls.run_above + 1 end,
  clear_cell_output = function(self) calls.clear_output = calls.clear_output + 1 end,
  reopen_closed_notebook = function(self) calls.reopen = calls.reopen + 1 end,
  open_title = function(self, title) calls.open_title = calls.open_title + 1; return true end,
  duplicate_cell = function(self) calls.duplicate = calls.duplicate + 1 end,
  close_other_notebooks = function(self) calls.close_others = calls.close_others + 1; return 0, 0 end,
  tree_sort = "name",
  tree_expanded = {},
  library_items = function(self, query)
    return {
      { path = "notebooks/a.luanb", name = "a.luanb", kind = "file",
        depth = 0 },
      { path = "notebooks/work", name = "work", kind = "directory",
        depth = 0 },
    }
  end,
  open_path = function(self, path) calls.open_path = calls.open_path + 1; return true end,
  cycle_tree_sort = function(self) calls.cycle_sort = calls.cycle_sort + 1 end,
  save_all = function(self) calls.save_all = calls.save_all + 1 end,
  restart_all_kernels = function(self) calls.restart_all = calls.restart_all + 1 end,
  set_outputs_expanded = function(self, expanded)
    calls.expand_outputs = calls.expand_outputs + (expanded and 1 or -1)
  end,
  set_tab = function(self, index) self.active = index end,
  restart_and_run_all = function(self) calls.restart = calls.restart + 1 end,
  set_headings_collapsed = function(self, collapsed)
    calls.collapse = calls.collapse + (collapsed and 1 or -1)
  end,
}
local ui = UI.new(app)

ui:keypressed("down", { alt = true })
assert(calls.move == 1, "Alt+Down does not move a cell down")
ui:keypressed("up", { alt = true })
assert(calls.move == 0, "Alt+Up does not move a cell up")

ui:keypressed("down", { ctrl = true, shift = true })
assert(calls.heading == 1, "Ctrl+Shift+Down does not go to the next heading")
ui:keypressed("up", { ctrl = true, shift = true })
assert(calls.heading == 0, "Ctrl+Shift+Up does not go to the previous heading")

ui:keypressed("c", { ctrl = true, shift = true })
assert(calls.copy == 1, "Ctrl+Shift+C does not copy the cell source")
ui:keypressed("c", { ctrl = true, alt = true })
assert(calls.copy_output == 1, "Ctrl+Alt+C does not copy the cell output")
ui:keypressed("return", { ctrl = true, alt = true })
assert(calls.run_below == 1, "Ctrl+Alt+Enter does not run the cell and below")
ui:keypressed("up", { ctrl = true, alt = true })
assert(calls.run_above == 1, "Ctrl+Alt+Up does not run the cell and above")
notebook:select(2)
notebook.cells[2].cursor = #notebook.cells[2].source + 1
ui:keypressed("v", { ctrl = true })
assert(notebook.cells[2].source:sub(-6) == "pasted",
  "Ctrl+V does not paste into the selected cell")
notebook:undo()
ui:keypressed("x", { ctrl = true, alt = true })
assert(calls.clear_output == 1, "Ctrl+Alt+X does not clear the cell output")
ui:keypressed("t", { ctrl = true, alt = true })
assert(calls.reopen == 1, "Ctrl+Alt+T does not reopen the last tab")
ui:keypressed("s", { ctrl = true, alt = true })
assert(calls.save_all == 1, "Ctrl+Alt+S does not save all notebooks")
ui:keypressed("k", { ctrl = true, alt = true })
assert(calls.restart_all == 1, "Ctrl+Alt+K does not restart all kernels")
ui:keypressed("d", { alt = true })
assert(calls.duplicate == 1, "Alt+D does not duplicate the selected cell")
ui:keypressed("w", { ctrl = true, alt = true })
assert(calls.close_others == 1, "Ctrl+Alt+W does not close other tabs")
ui:keypressed("g", { ctrl = true, alt = true })
assert(ui.show_cell_prompt, "Ctrl+Alt+G does not open the cell prompt")
ui:textinput("3")
ui:keypressed("return")
assert(notebook.active == 3, "go-to-cell did not select cell 3")
assert(not ui.show_cell_prompt, "go-to-cell prompt did not close")
ui:keypressed("f5", { ctrl = true, shift = true })
assert(calls.restart == 1, "Ctrl+Shift+F5 does not restart and run all")

local commands = {}
for _, command in ipairs(ui:palette_commands()) do
  commands[command.id] = command.label
end
for _, id in ipairs({ "restart-run-all", "copy-cell", "paste-cell", "copy-output",
    "run-below", "run-above", "save-all", "restart-all-kernels",
    "expand-outputs", "collapse-outputs", "clear-cell-output", "reopen-closed", "go-to-cell",
    "close-others", "duplicate-cell", "tree-sort", "prev-heading", "next-heading",
    "collapse-headings", "expand-headings" }) do
  assert(commands[id] ~= nil, "missing palette command: " .. id)
end

ui:run_palette_command("move-up")
ui:run_palette_command("move-down")
assert(calls.move == 0, "palette move commands are miswired")
ui:run_palette_command("next-heading")
ui:run_palette_command("prev-heading")
assert(calls.heading == 0, "palette heading commands are miswired")
ui:run_palette_command("copy-cell")
assert(calls.copy == 2, "palette copy command is miswired")
notebook:select(2)
notebook.cells[2].cursor = #notebook.cells[2].source + 1
ui:run_palette_command("paste-cell")
assert(notebook.cells[2].source:sub(-6) == "pasted",
  "palette paste command is miswired")
notebook:undo()
ui:run_palette_command("copy-output")
assert(calls.copy_output == 2, "palette copy-output command is miswired")
ui:run_palette_command("run-below")
assert(calls.run_below == 2, "palette run-below command is miswired")
ui:run_palette_command("run-above")
assert(calls.run_above == 2, "palette run-above command is miswired")
ui:run_palette_command("clear-cell-output")
assert(calls.clear_output == 2, "palette clear-cell-output is miswired")
ui:run_palette_command("reopen-closed")
assert(calls.reopen == 2, "palette reopen-closed is miswired")
ui:run_palette_command("save-all")
assert(calls.save_all == 2, "palette save-all is miswired")
ui:run_palette_command("restart-all-kernels")
assert(calls.restart_all == 2, "palette restart-all is miswired")
ui:run_palette_command("expand-outputs")
ui:run_palette_command("collapse-outputs")
assert(calls.expand_outputs == 0, "palette output-fold commands are miswired")
ui:run_palette_command("duplicate-cell")
assert(calls.duplicate == 2, "palette duplicate-cell is miswired")
ui:run_palette_command("close-others")
assert(calls.close_others == 2, "palette close-others is miswired")
ui:run_palette_command("tree-sort")
assert(calls.cycle_sort == 1, "palette tree-sort is miswired")
ui:open_tree()
assert(ui.show_tree, "open_tree did not show the filetree")
ui:keypressed("down")
assert(ui.tree_selected == 2, "filetree Down did not move the selection")
ui:keypressed("down")
assert(ui.tree_selected == 2, "filetree Down exceeded the item count")
ui:keypressed("up")
ui:keypressed("return")
assert(calls.open_path == 1 and not ui.show_tree,
  "filetree Enter did not open the selected file")
ui:run_palette_command("go-to-cell")
assert(ui.show_cell_prompt, "palette go-to-cell did not open the prompt")
ui:keypressed("escape")
ui:run_palette_command("restart-run-all")
assert(calls.restart == 2, "palette restart-run-all is miswired")
ui:run_palette_command("collapse-headings")
ui:run_palette_command("expand-headings")
assert(calls.collapse == 0, "palette heading-fold commands are miswired")

ui:keypressed("f11")
assert(ui.show_outline, "F11 does not open the outline")
ui:textinput("TWO")
assert(#ui.outline_matches == 1, "outline filter did not narrow to one heading")
ui:keypressed("return")
assert(notebook.active == 3, "outline Enter did not jump to the heading")
assert(not ui.show_outline, "outline did not close after a jump")

ui:keypressed("t", { ctrl = true })
assert(ui.show_tags, "Ctrl+T does not open the tag index")
ui:textinput("ALP")
assert(#ui.tag_entries == 1, "tag filter did not narrow to one tag")
ui:keypressed("return")
assert(not ui.show_tags, "tag Enter did not close the overlay")
assert(ui.find_query == "#alpha", "tag Enter did not open the tag search")
ui:keypressed("escape")
assert(not ui.show_find, "find overlay did not close")

ui.link_rects = { { x = 0, y = 0, w = 20, h = 20, target = "Two" } }
ui:mousepressed(5, 5, 1)
assert(calls.open_title == 1, "clicking a wiki link did not open its title")

notebook.cells[4].source = "- [ ] task"
ui.link_rects = {}
ui.task_rects = { { x = 0, y = 0, w = 20, h = 20, cell = 4, line = 1 } }
ui:mousepressed(5, 5, 1)
assert(notebook.cells[4].source == "- [x] task",
  "clicking a preview task marker did not check it")
assert(app.status == "checked task", "task click status is wrong")

print("workflow shortcut tests ok")
