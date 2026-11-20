local root = (arg and arg[0] or "tests/nvim_session.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Session = require("notebook.nvim.session")

local session = Session.new({ cols = 40, rows = 10 })
local ok, err = session:set_lines({ "local x = 1", "print(x)" }, 1)
assert(ok, tostring(err))
local deadline = os.clock() + 3
while os.clock() < deadline do
  session:update()
  if session.grid:line(0):find("local x", 1, true) then break end
end
print("LINES", table.concat(session:get_lines(), "|"))
print("GRID", session.grid:line(0))
local line = session.grid:line(0)
assert(line:find("local x", 1, true), "grid did not show buffer: " .. line)
local lines = session:get_lines()
assert(#lines == 2 and lines[2] == "print(x)", tostring(#lines))
session:input("dd")
session:update()
for _ = 1, 20 do session:update(); os.execute("sleep 0.02") end
lines = session:get_lines()
assert(#lines == 1 and lines[1] == "print(x)", "dd did not delete: " ..
  table.concat(lines, "|"))
session:close()

local dead = Session.new({ cols = 20, rows = 5 })
pcall(function() dead:command("qall!") end)
for _ = 1, 40 do dead:update(); os.execute("sleep 0.02") end
assert(dead.exited, "EOF was not detected")
local dead_lines, dead_error = dead:get_lines()
assert(dead_lines == nil and dead_error ~= nil, "get_lines after EOF")
dead:close()
print("nvim dead peer ok")

local modes = Session.new({ cols = 20, rows = 5 })
for _ = 1, 20 do modes:update(); os.execute("sleep 0.02") end
assert(modes.grid.mode == "normal", tostring(modes.grid.mode))
modes:input("i")
for _ = 1, 20 do modes:update(); os.execute("sleep 0.02") end
assert(modes.grid.mode == "insert", tostring(modes.grid.mode))
modes:input("<Esc>")
for _ = 1, 20 do modes:update(); os.execute("sleep 0.02") end
assert(modes.grid.mode == "normal", tostring(modes.grid.mode))
modes:close()
print("nvim modes ok")
local popup = Session.new({ cols = 40, rows = 10 })
popup:command("set completeopt=menu,menuone,noselect")
popup:set_lines({ "print(1)", "pairs({})" }, 1)
popup:input("<Esc>Gopr")
for _ = 1, 30 do popup:update(); os.execute("sleep 0.02") end
popup:input("<C-n>")
for _ = 1, 40 do popup:update(); os.execute("sleep 0.02") end
assert(popup.grid.popupmenu, "popupmenu did not arrive")
assert(popup.grid.popupmenu.items[1][1] == "print",
  tostring(popup.grid.popupmenu.items[1][1]))
popup:close()
print("nvim popupmenu ok")
print("nvim session ok")
