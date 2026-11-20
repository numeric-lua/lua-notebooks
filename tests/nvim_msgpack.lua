local root = (arg and arg[0] or "tests/nvim_msgpack.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Msgpack = require("notebook.nvim.msgpack")
local function f32(bytes)
  local value, position = Msgpack.decode(bytes, 1)
  assert(type(value) == "number" and position == 6, tostring(value))
  return value
end
assert(math.abs(f32(string.char(0xca, 0x3f, 0xc0, 0x00, 0x00)) - 1.5) < 1e-9)
assert(math.abs(f32(string.char(0xca, 0xbf, 0x80, 0x00, 0x00)) + 1.0) < 1e-9)
assert(f32(string.char(0xca, 0x00, 0x00, 0x00, 0x00)) == 0)
print("nvim msgpack ok")
