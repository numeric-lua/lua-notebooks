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
  new_notebook = 0, create_folder = 0, rename_folder = 0,
  delete_path = 0, expand_folders = 0,
  expand_outputs = 0, comment_line = 0, shift_line = 0, duplicate_line = 0,
  indent_line = 0,
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
  new_notebook = function(self, folder) calls.new_notebook = calls.new_notebook + 1; calls.new_folder = folder end,
  create_folder = function(self, name, parent) calls.create_folder = calls.create_folder + 1; calls.folder_parent = parent end,
  rename_folder = function(self, path, name) calls.rename_folder = calls.rename_folder + 1; return true end,
  delete_notebook = function(self, path) calls.delete_path = calls.delete_path + 1 end,
  set_folders_expanded = function(self, expanded) calls.expand_folders = calls.expand_folders + (expanded and 1 or -1) end,
  save_all = function(self) calls.save_all = calls.save_all + 1 end,
  restart_all_kernels = function(self) calls.restart_all = calls.restart_all + 1 end,
  set_outputs_expanded = function(self, expanded)
    calls.expand_outputs = calls.expand_outputs + (expanded and 1 or -1)
  end,
  toggle_line_comment = function(self) calls.comment_line = calls.comment_line + 1 end,
  shift_current_line = function(self, delta) calls.shift_line = calls.shift_line + delta end,
  duplicate_current_line = function(self) calls.duplicate_line = calls.duplicate_line + 1 end,
  indent_current_line = function(self, delta) calls.indent_line = calls.indent_line + delta end,
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
ui:keypressed("/", { ctrl = true })
assert(calls.comment_line == 1, "Ctrl+/ does not toggle the line comment")
ui:keypressed("down", { alt = true, shift = true })
assert(calls.shift_line == 1, "Alt+Shift+Down does not move the line")
ui:keypressed("up", { alt = true, shift = true })
assert(calls.shift_line == 0, "Alt+Shift+Up does not move the line")
ui:keypressed("d", { ctrl = true, shift = true })
assert(calls.duplicate_line == 1, "Ctrl+Shift+D does not duplicate the line")
ui:keypressed("]", { ctrl = true })
ui:keypressed("[", { ctrl = true })
assert(calls.indent_line == 0, "Ctrl+] / [ do not indent and outdent")
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
    "close-others", "duplicate-cell", "tree-expand-all", "tree-collapse-all",
    "comment-line", "move-line-up",
    "move-line-down", "duplicate-line", "indent-line", "outdent-line",
    "delete-word-back", "delete-word-forward", "join-line", "cell-start",
    "cell-end", "go-to-line", "tree-sort", "prev-heading", "next-heading",
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
ui:run_palette_command("comment-line")
assert(calls.comment_line == 2, "palette comment-line is miswired")
ui:run_palette_command("move-line-up")
ui:run_palette_command("move-line-down")
assert(calls.shift_line == 0, "palette line-move commands are miswired")
ui:run_palette_command("duplicate-line")
assert(calls.duplicate_line == 2, "palette duplicate-line is miswired")
ui:run_palette_command("indent-line")
ui:run_palette_command("outdent-line")
assert(calls.indent_line == 0, "palette indent commands are miswired")
notebook:select(2)
notebook.cells[2].source = "alpha beta"
notebook.cells[2].cursor = #notebook.cells[2].source + 1
ui:run_palette_command("delete-word-back")
assert(notebook.cells[2].source == "alpha ",
  "palette delete-word-back is miswired")
notebook.cells[2].source = "alpha beta"
notebook.cells[2].cursor = 1
ui:run_palette_command("delete-word-forward")
assert(notebook.cells[2].source == "beta",
  "palette delete-word-forward is miswired")
notebook.cells[2].source = "a\nb"
notebook.cells[2].cursor = 1
ui:run_palette_command("cell-end")
assert(notebook.cells[2].cursor == 4, "palette cell-end is miswired")
ui:run_palette_command("cell-start")
assert(notebook.cells[2].cursor == 1, "palette cell-start is miswired")
notebook.cells[2].source = "a\nb"
ui:run_palette_command("join-line")
assert(notebook.cells[2].source == "a b", "palette join-line is miswired")
ui:run_palette_command("go-to-line")
assert(ui.show_cell_prompt and ui.cell_prompt_kind == "line",
  "palette go-to-line did not open the line prompt")
ui:keypressed("escape")
ui:run_palette_command("close-others")
assert(calls.close_others == 2, "palette close-others is miswired")
ui:run_palette_command("tree-sort")
assert(calls.cycle_sort == 1, "palette tree-sort is miswired")
ui:open_tree()
assert(ui.show_tree, "open_tree did not show the filetree")
ui:keypressed("down")
assert(ui.tree_selected == 2, "filetree Down did not move the selection")
ui:keypressed("right")
assert(app.tree_expanded["notebooks/work"] == true,
  "filetree Right did not expand the folder")
ui:keypressed("left")
assert(app.tree_expanded["notebooks/work"] == false,
  "filetree Left did not collapse the folder")
ui:keypressed("down")
assert(ui.tree_selected == 2, "filetree Down exceeded the item count")
ui:keypressed("home")
assert(ui.tree_selected == 1, "filetree Home did not jump to the first row")
ui:keypressed("end")
assert(ui.tree_selected == 2, "filetree End did not jump to the last row")
ui:keypressed("up")
ui:keypressed("return")
assert(calls.open_path == 1 and not ui.show_tree,
  "filetree Enter did not open the selected file")
ui.tree_selected = 2
assert(ui:tree_parent_path() == "notebooks/work",
  "tree_parent_path did not choose the selected folder")
ui:open_tree()
ui.tree_selected = 2
ui.tree_rects = { { x = 0, y = 0, w = 20, h = 20, action = "new" } }
ui:mousepressed(5, 5, 1)
assert(calls.new_notebook == 1 and calls.new_folder == "notebooks/work",
  "New notebook did not use the selected folder")
ui.show_tree = false
ui.folder_prompt = { value = "child", parent = "notebooks/work" }
ui:keypressed("return")
assert(calls.create_folder == 1 and calls.folder_parent == "notebooks/work",
  "folder creation did not inherit the selected folder")
ui.rename_prompt = {
  old = "notebooks/work", value = "renamed", kind = "folder",
}
ui:keypressed("return")
assert(calls.rename_folder == 1, "folder rename prompt was miswired")
ui.confirm_delete = {
  name = "work", path = "notebooks/work", kind = "folder",
}
ui:keypressed("return")
assert(calls.delete_path == 1, "folder delete confirmation was miswired")
ui:run_palette_command("tree-expand-all")
ui:run_palette_command("tree-collapse-all")
assert(calls.expand_folders == 0,
  "palette folder expand/collapse commands are miswired")
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

local original_search_cell = notebook.cells[2].source
local original_markdown = notebook.cells[4].source
local needle_lines = {}
for line = 1, 15 do needle_lines[line] = "needle " .. line end
notebook.cells[2].source = table.concat(needle_lines, "\n")
notebook.cells[4].source = "needle prose"
ui:open_find()
ui.find_query = "needle"
ui:update_find()
assert(#ui.find_results == 16, "find did not collect every matching row")
ui:keypressed("pagedown")
assert(ui.find_selected == 11 and ui.find_offset == 6,
  "find PageDown did not advance one page")
ui:keypressed("home")
assert(ui.find_selected == 1 and ui.find_offset == 0,
  "find Home did not return to the first row")
ui:keypressed("end")
assert(ui.find_selected == 16 and ui.find_offset == 6,
  "find End did not jump to the last page")
ui:keypressed("k", { alt = true })
assert(ui.find_kind == "code" and #ui.find_results == 15,
  "find Alt+K did not select code cells")
ui:keypressed("k", { alt = true })
assert(ui.find_kind == "markdown" and #ui.find_results == 1,
  "find Alt+K did not select markdown cells")
ui:keypressed("k", { alt = true })
assert(ui.find_kind == "all" and #ui.find_results == 16,
  "find Alt+K did not return to all cells")
ui.find_rects = { { x = 0, y = 0, w = 20, h = 20, index = 11 } }
ui:mousepressed(5, 5, 1)
assert(not ui.show_find and notebook.active == 2,
  "clicking a paged find result did not open it")

ui:open_global_find()
ui.global_find_query = "needle"
ui:update_global_find()
assert(#ui.global_find_results == 16,
  "global find did not collect every matching row")
ui:keypressed("pagedown")
assert(ui.global_find_selected == 11 and ui.global_find_offset == 6,
  "global find PageDown did not advance one page")
ui:keypressed("k", { alt = true })
assert(ui.global_find_kind == "code" and
  #ui.global_find_results == 15,
  "global find Alt+K did not select code cells")
ui:keypressed("escape")
notebook.cells[2].source = original_search_cell
notebook.cells[4].source = original_markdown
notebook:select(4)
ui:keypressed("l", { ctrl = true, alt = true })
ui:textinput("2")
ui:keypressed("return")
local line_two = notebook.cells[4].source:find("\n", 1, true) + 1
assert(notebook.cells[4].cursor == line_two,
  "Ctrl+Alt+L did not move the caret to line 2")
assert(not ui.show_cell_prompt, "line prompt did not close")

notebook:select(2)
notebook.cells[2].source = "alpha beta"
notebook.cells[2].cursor = 1
ui:keypressed("right", { ctrl = true })
assert(notebook.cells[2].cursor == 7,
  "Ctrl+Right did not move to the next word")
ui:keypressed("left", { ctrl = true })
assert(notebook.cells[2].cursor == 1,
  "Ctrl+Left did not move to the previous word")
notebook.cells[2].cursor = #notebook.cells[2].source + 1
ui:keypressed("backspace", { ctrl = true })
assert(notebook.cells[2].source == "alpha ",
  "Ctrl+Backspace did not delete the previous word")
notebook.cells[2].source = "alpha beta"
notebook.cells[2].cursor = 1
ui:keypressed("delete", { ctrl = true })
assert(notebook.cells[2].source == "beta",
  "Ctrl+Delete did not delete the next word")
notebook.cells[2].source = "a\nb"
notebook.cells[2].cursor = 2
ui:keypressed("home", { ctrl = true })
assert(notebook.cells[2].cursor == 1, "Ctrl+Home did not go to cell start")
ui:keypressed("end", { ctrl = true })
assert(notebook.cells[2].cursor == 4, "Ctrl+End did not go to cell end")
notebook.cells[2].source = "alpha\n  beta"
notebook.cells[2].cursor = 3
ui:keypressed("j", { ctrl = true })
assert(notebook.cells[2].source == "alpha beta",
  "Ctrl+J did not join the next line")

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

ui:run_palette_command("move-up")
ui:keypressed("f1")
ui.palette_query = ""
local palette_items = ui:palette_commands()
assert(palette_items[1].id == "move-up",
  "recent palette command was not moved to the top")
assert(#palette_items > 12, "palette fixture is too short for paging")
ui:keypressed("pagedown")
assert(ui.palette_selected == 13 and ui.palette_offset == 12,
  "palette PageDown did not advance one page")
ui:keypressed("home")
assert(ui.palette_selected == 1 and ui.palette_offset == 0,
  "palette Home did not return to the first command")
ui:keypressed("end")
assert(ui.palette_selected == #palette_items,
  "palette End did not select the last command")
ui:keypressed("escape")

ui.tag_entries = {}
for index = 1, 12 do
  ui.tag_entries[index] = { tag = "t" .. index, count = 1, notebooks = {} }
end
ui.show_tags = true
ui.tag_selected = 1
ui:keypressed("pagedown")
assert(ui.tag_selected == 11 and ui.tag_offset == 2,
  "tag PageDown did not advance one page")
ui:keypressed("home")
assert(ui.tag_selected == 1 and ui.tag_offset == 0,
  "tag Home did not return to the first tag")
ui.show_tags = false

ui.outline_matches = {}
for index = 1, 15 do
  ui.outline_matches[index] = { index = index, level = 1,
    text = "Heading " .. index, collapsed = false }
end
ui.show_outline = true
ui.outline_selected = 1
ui:keypressed("pagedown")
assert(ui.outline_selected == 13 and ui.outline_offset == 3,
  "outline PageDown did not advance one page")
ui:keypressed("home")
assert(ui.outline_selected == 1 and ui.outline_offset == 0,
  "outline Home did not return to the first heading")
ui.show_outline = false

local base_library_items = app.library_items
app.library_items = function(self, query)
  local items = {}
  for index = 1, 20 do
    items[index] = { path = "notebooks/n" .. index .. ".luanb",
      name = "n" .. index .. ".luanb", kind = "file", depth = 0 }
  end
  return items
end
ui:open_tree()
ui:keypressed("pagedown")
assert(ui.tree_selected == 15 and ui.tree_offset == 6,
  "filetree PageDown did not advance one page")
ui:keypressed("home")
assert(ui.tree_selected == 1 and ui.tree_offset == 0,
  "filetree Home did not return to the first row")
ui.show_tree = false
app.library_items = base_library_items

print("workflow shortcut tests ok")
