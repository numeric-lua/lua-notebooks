local script = arg and arg[0] or "tests/run.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
if root == "" then root = "." end
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local json = require("notebook.json")
local Notebook = require("notebook.model")
local Format = require("notebook.format")

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

current = "format"
test("round-trips a notebook", function()
  local notebook = Notebook.new({ name = "roundtrip.luanb",
    cells = { { kind = "code", source = "print(1)" },
              { kind = "markdown", source = "# hi" } } })
  notebook.cells[1].scene = { type = "luaplotlib", xlim = { 0, 1 } }
  local decoded = Format.decode(Format.encode(notebook))
  eq(decoded.name, "roundtrip.luanb")
  eq(#decoded.cells, 2)
  eq(decoded.cells[1].scene.type, "luaplotlib")
  eq(decoded.cells[2].source, "# hi")
end)
test("rejects an unsupported version", function()
  local ok = pcall(Format.decode, '{"version":2,"name":"x","cells":[{"kind":"code"}]}')
  eq(ok, false)
end)

current = "model"
test("demo has two notebooks", function()
  local notebooks = Notebook.demo()
  eq(#notebooks, 2)
  eq(#notebooks[1].cells, 6)
end)
test("inserts and deletes text at a cursor", function()
  local notebook = Notebook.new({ cells = { { kind = "code", source = "" } } })
  notebook:insert("print")
  notebook:backspace()
  eq(notebook:selected().source, "prin")
  notebook:newline()
  eq(notebook:selected().source, "prin\n")
  notebook:move_cursor(-2)
  notebook:insert("X")
  eq(notebook:selected().source, "priXn\n")
  notebook:delete()
  eq(notebook:selected().source, "priX\n")
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
test("validates extension manifests", function()
  local Manifest = require("extensions.manifest")
  local valid = Manifest.validate({ id = "foo", render = function() end })
  eq(valid ~= nil, true, "valid manifest")
  eq(Manifest.validate({ id = "Bad ID", render = function() end }) == nil,
    true, "invalid id")
  eq(Manifest.validate({ id = "foo" }) == nil, true, "missing render")
  eq(Manifest.validate({ id = "foo", render = function() end,
    pointer = 3 }) == nil, true, "bad callback")
end)
test("loads and validates extension modules", function()
  local Loader = require("extensions.loader")
  local modules = {
    ["extensions.alpha"] = { id = "alpha", render = function() end },
    ["extensions.bad"] = { id = "bad" },
  }
  local loaded, errors = Loader.discover({
    list = function() return { "alpha.lua", "bad.lua", "init.lua" } end,
    require = function(name)
      local value = modules[name]
      if value == nil then error("missing " .. name) end
      return value
    end,
    register = function(descriptor) return descriptor end,
  })
  eq(#loaded, 1)
  eq(#errors, 1)
  eq(loaded[1].id, "alpha")
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