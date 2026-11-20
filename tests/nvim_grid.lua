local root = (arg and arg[0] or "tests/nvim_grid.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Grid = require("notebook.nvim.grid")

local grid = Grid.new(20, 5)
grid:apply_redraw({
  { "default_colors_set", 0xffffff, 0x000000, 0, 0, 0 },
  { "hl_attr_define",
    { 1, { foreground = 0xff0000, bold = true }, {}, {} } },
  { "grid_line",
    { 1, 0, 0, { { "h", 1 }, { "i" } }, false },
    { 1, 1, 0, { { "l", 1, 2 }, { "o" } }, false },
  },
  { "grid_cursor_goto", { 1, 1, 3 } },
})
assert(grid:line(0):sub(1, 2) == "hi", grid:line(0))
assert(grid:line(1):sub(1, 3) == "llo", grid:line(1))
assert(grid.cursor.row == 1 and grid.cursor.col == 3)
assert(grid.highlights[1].foreground == 0xff0000)
grid:apply_redraw({ { "grid_scroll", { 1, 0, 5, 0, 20, 1 } } })
assert(grid:line(0):sub(1, 3) == "llo", grid:line(0))
assert(grid:line(4):match("^%s+$"), "bottom row should be blank")
grid:apply_redraw({ { "grid_resize", { 1, 10, 3 } } })
assert(#grid:line(0) == 10)
print("nvim grid ok")


local flat = Grid.new(10, 3)
flat:apply_redraw({
  { "grid_resize", 1, 10, 3 },
  { "grid_line", 1, 0, 0, { { "f", 1 }, { "l" }, { "a", 1 }, { "t" } }, false },
  { "grid_cursor_goto", 1, 1, 2 },
})
assert(flat:line(0):sub(1, 4) == "flat", flat:line(0))
assert(flat.cursor.row == 1 and flat.cursor.col == 2)
flat:apply_redraw({ { "grid_scroll", 1, 0, 3, 0, 10, 1 } })
assert(flat:line(0):match("^%s+$"))
print("nvim flat grid ok")

local popup = Grid.new(20, 5)
popup:apply_redraw({
  { "popupmenu_show", { { "print", "f" }, { "pairs", "f" } }, 0, 1, 2 },
})
assert(popup.popupmenu and #popup.popupmenu.items == 2)
assert(popup.popupmenu.selected == 1)
popup:apply_redraw({ { "popupmenu_select", 1 } })
assert(popup.popupmenu.selected == 2)
popup:apply_redraw({ { "popupmenu_hide" } })
assert(popup.popupmenu == nil)
local nested_popup = Grid.new(20, 5)
nested_popup:apply_redraw({ { "popupmenu_show",
  { { { "local", "k" } }, 0, 0, 0 } } })
assert(nested_popup.popupmenu and #nested_popup.popupmenu.items == 1)
print("nvim popupmenu ok")
