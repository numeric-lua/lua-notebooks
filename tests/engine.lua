local root = (arg and arg[0] or "tests/engine.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Engine = require("kernel.engine")
local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; io.write(".")
  else failed = failed + 1
    io.write("F\n  " .. name .. ": " .. tostring(err) .. "\n")
  end
end
local function eq(a, b)
  if a ~= b then error(tostring(a) .. " ~= " .. tostring(b), 2) end
end

test("persists globals in one kernel", function()
  local engine = Engine.new()
  local first = engine:run({ id = 1, code = "x = (x or 0) + 1; return x" })
  local second = engine:run({ id = 2, code = "x = (x or 0) + 1; return x" })
  eq(first.ok, true)
  eq(first.value, "1")
  eq(second.value, "2")
end)

test("isolates kernels", function()
  local a, b = Engine.new(), Engine.new()
  eq(a:run({ id = 1, code = "y = 4; return y" }).value, "4")
  eq(b:run({ id = 2, code = "return y" }).value, nil)
end)

test("captures print and io.write", function()
  local engine = Engine.new()
  local message = engine:run({ id = 1,
    code = "print('hello', 2); io.write(' world')" })
  eq(message.output, "hello\t2\n world")
end)

test("returns errors without escaping", function()
  local engine = Engine.new()
  local message = engine:run({ id = 1, code = "error('boom')" })
  eq(message.ok, false)
  eq(message.value:find("boom") ~= nil, true)
end)

test("reports execution elapsed seconds", function()
  local engine = Engine.new()
  local message = engine:run({ id = 1, code = "local x = 0; for i = 1, 1000 do x = x + i end" })
  assert(type(message.elapsed) == "number", "missing elapsed")
  assert(message.elapsed >= 0, "negative elapsed")
end)

test("extracts scenes", function()
  local engine = Engine.new()
  local message = engine:run({ id = 1,
    code = "return { scene = { type = 'cube' } }" })
  eq(message.ok, true)
  eq(message.scene.type, "cube")
  eq(message.value, nil)
end)

test("resets kernel state", function()
  local engine = Engine.new()
  engine:run({ id = 1, code = "x = 10" })
  engine:reset()
  eq(engine:run({ id = 2, code = "return x" }).value, nil)
end)

local bounded = Engine.new({ max_output = 32 })
local result = bounded:run({ id = 3, code = "print(string.rep('x', 200))" })
assert(result.ok)
assert(#result.output < 200 and result.output:find("output truncated", 1, true))
print("bounded output ok")

io.write(string.format("\n%d engine tests, %d passed, %d failed\n",
  passed + failed, passed, failed))
if failed > 0 then os.exit(1) end

