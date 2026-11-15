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
local delimited = assert(Engine.typeset("\\left(\\frac{a}{b}\\right)",
  { measure = measure }))
assert(delimited and delimited.box.w > 0)
local spaced = assert(Engine.typeset("a\\,b\\quad c", { measure = measure }))
assert(spaced.box.w > 0)
local text_group = assert(Engine.typeset("\\text{if }x>0", { measure = measure }))
assert(text_group.box.w > 0)
local tight = assert(Engine.typeset("a+b", { measure = measure }))
local relation = assert(Engine.typeset("a=b", { measure = measure }))
assert(relation.box.w > tight.box.w - 1)
local unary = assert(Engine.typeset("-x", { measure = measure }))
local binary = assert(Engine.typeset("a - x", { measure = measure }))
assert(binary.box.w > unary.box.w)
local punct = assert(Engine.typeset("a,b", { measure = measure }))
assert(punct.box.w > Engine.typeset("ab", { measure = measure }).box.w)
local styled = assert(Engine.typeset("\\mathbf{F}=m\\mathit{a}",
  { measure = measure }))
assert(styled.box.w > 0)
local wide = assert(Engine.typeset(
  "\\frac{abcdefghijklmnop}{qrstuvwxyz}", { measure = measure,
    max_width = 80 }))
assert(wide.box.w <= 80.0001, wide.box.w)
local stretched = assert(Engine.typeset(
  "\\left(\\frac{a}{b}\\right)", { measure = measure }))
assert(stretched.box.items[1].box ~= nil)
assert(stretched.box.w > 0)
print("math engine tests ok")
