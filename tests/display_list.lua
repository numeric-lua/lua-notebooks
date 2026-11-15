local root = (arg and arg[0] or "tests/display_list.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local DisplayList = require("extensions.display_list")
local function eq(a, b) if a ~= b then error(tostring(a) .. " ~= " .. tostring(b), 2) end end
local descriptor = {
  id = "bars", title = "Bars", display = { clear = { 0, 0, 0, 1 }, commands = {
    { op = "color", rgba = { 1, 0.5, 0.2, 1 } },
    { op = "cube", x = 0, y = 0, z = 0, size = 1 },
  } },
}
local valid = assert(DisplayList.validate(descriptor))
eq(valid.tier, "declarative")
local calls = {}
local pass = setmetatable({}, { __index = function(_, name)
  return function(_, ...) calls[#calls + 1] = { name = name, args = { ... } } end
end })
DisplayList.replay(pass, valid, 800, 600)
assert(#calls >= 4)
eq(calls[1].name, "setClear")
assert(DisplayList.validate({ id = "x", display = { commands = {
  { op = "exec", code = "os.exit()" } } } }) == nil)
assert(DisplayList.validate({ id = "x", display = { commands = {
  { op = "color", rgba = { 2, 0, 0 } } } } }) == nil)
print("display-list tests ok")
