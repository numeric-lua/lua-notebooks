local root = (arg and arg[0] or "tests/math_engine.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Engine = require("notebook.math.engine")
local function eq(a, b) if a ~= b then error(tostring(a) .. " ~= " .. tostring(b), 2) end end
local measure = {
  width = function(text, scale) return #text * 9 * scale end,
  ink = function(text, scale) return 9 * scale, 2 * scale end,
}
local fraction = assert(Engine.typeset("\\frac{a}{b}", { measure = measure }))
assert(fraction.box.h + fraction.box.d > 20)
assert(#fraction.box.items[1].box.ops == 1)
local root = assert(Engine.typeset("\\sqrt{x}", { measure = measure }))
assert(root.box.h > 9)
assert(#root.box.items[1].box.ops == 3)
local script = assert(Engine.typeset("x^2", { measure = measure }))
assert(script.box.h > 9)
print("math engine tests ok")
