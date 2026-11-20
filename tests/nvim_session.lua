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
print("nvim session ok")
