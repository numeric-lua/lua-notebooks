-- Workflow shortcut wiring.  LÖVR is stubbed so the keyboard dispatch and
-- command-palette routing can be checked without opening a window.
local root = (arg and arg[0] or "tests/workflow.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

lovr = { system = { isKeyDown = function() return false end } }

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
  open_title = 0,
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
  clear_cell_output = function(self) calls.clear_output = calls.clear_output + 1 end,
  reopen_closed_notebook = function(self) calls.reopen = calls.reopen + 1 end,
  open_title = function(self, title) calls.open_title = calls.open_title + 1; return true end,
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
ui:keypressed("x", { ctrl = true, alt = true })
assert(calls.clear_output == 1, "Ctrl+Alt+X does not clear the cell output")
ui:keypressed("t", { ctrl = true, alt = true })
assert(calls.reopen == 1, "Ctrl+Alt+T does not reopen the last tab")
ui:keypressed("f5", { ctrl = true, shift = true })
assert(calls.restart == 1, "Ctrl+Shift+F5 does not restart and run all")

local commands = {}
for _, command in ipairs(ui:palette_commands()) do
  commands[command.id] = command.label
end
for _, id in ipairs({ "restart-run-all", "copy-cell", "copy-output",
    "run-below", "clear-cell-output", "reopen-closed", "prev-heading",
    "next-heading", "collapse-headings", "expand-headings" }) do
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
ui:run_palette_command("copy-output")
assert(calls.copy_output == 2, "palette copy-output command is miswired")
ui:run_palette_command("run-below")
assert(calls.run_below == 2, "palette run-below command is miswired")
ui:run_palette_command("clear-cell-output")
assert(calls.clear_output == 2, "palette clear-cell-output is miswired")
ui:run_palette_command("reopen-closed")
assert(calls.reopen == 2, "palette reopen-closed is miswired")
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
