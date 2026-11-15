local script = arg and arg[0] or "tests/run.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
if root == "" then root = "." end
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local json = require("notebook.json")
local Notebook = require("notebook.model")

local passed, failed = 0, 0
local failures = {}
local current = "?"

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write(".")
  else
    failed = failed + 1
    failures[#failures + 1] = string.format("[%s] %s\n  %s", current, name,
      tostring(err))
    io.write("F")
  end
  io.flush()
end

local function eq(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label or "value",
      tostring(expected), tostring(actual)), 2)
  end
end

current = "json"
test("round-trips notebook data", function()
  local source = { name = "x", cells = { { kind = "code", source = "print(1)" } } }
  local decoded = json.decode(json.encode(source))
  eq(decoded.name, "x")
  eq(decoded.cells[1].source, "print(1)")
end)
test("preserves null sentinel", function()
  local decoded = json.decode('{"x":null}')
  eq(decoded.x, json.null)
end)

current = "model"
test("demo has two notebooks", function()
  local notebooks = Notebook.demo()
  eq(#notebooks, 2)
  eq(#notebooks[1].cells, 5)
end)
test("inserts and deletes text", function()
  local notebook = Notebook.new({ cells = { { kind = "code", source = "" } } })
  notebook:insert("print")
  notebook:backspace()
  eq(notebook:selected().source, "prin")
  notebook:newline()
  eq(notebook:selected().source, "prin\n")
end)
test("adds and selects cells", function()
  local notebook = Notebook.new({ cells = { { kind = "code", source = "" } } })
  notebook:add_cell("code")
  eq(#notebook.cells, 2)
  eq(notebook.active, 2)
  notebook:move(-1)
  eq(notebook.active, 1)
end)
test("stores execution results", function()
  local notebook = Notebook.new({ cells = { { kind = "code", source = "" } } })
  notebook:set_result(1, { ok = true, output = "hi", value = "42" })
  eq(notebook.cells[1].output, "hi")
  eq(notebook.cells[1].running, false)
end)
test("records errors", function()
  local notebook = Notebook.new({ cells = { { kind = "code", source = "" } } })
  notebook:set_result(1, { ok = false, output = "", value = "boom" })
  eq(notebook.cells[1].error, "boom")
end)

current = "extensions"
test("registers and resolves extension renderers", function()
  local Extensions = require("extensions")
  eq(Extensions.get("cube") ~= nil, true, "cube extension")
  Extensions.register("dummy", { render = function() end })
  eq(Extensions.get("dummy") ~= nil, true, "dummy extension")
end)

io.write(string.format("\n\n%d tests, %d passed, %d failed\n", passed + failed,
  passed, failed))
if failed > 0 then
  for _, failure in ipairs(failures) do io.write("\n" .. failure .. "\n") end
  os.exit(1)
end