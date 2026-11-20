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
  eq(#notebooks[1].cells, 11)
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

current = "scroll"
test("max scroll depends only on content, not current offset", function()
  local Scroll = require("ui.scroll")
  eq(Scroll.max_scroll(1000, 800), 306)
  eq(Scroll.max_scroll(1000, 800), 306)
end)
test("target scroll is stable for a tall final cell", function()
  local Scroll = require("ui.scroll")
  local first = Scroll.target_scroll(0, 700, 500, 800, 1200)
  local second = Scroll.target_scroll(first, 700 - first, 500, 800, 1200)
  eq(first, second)
  eq(first <= Scroll.max_scroll(1200, 800), true)
end)

current = "extension browser"
test("can disable and re-enable a renderer", function()
  local Extensions = require("extensions")
  eq(Extensions.is_enabled("cube"), true)
  Extensions.set_enabled("cube", false)
  eq(Extensions.get("cube"), nil)
  eq(Extensions.is_enabled("cube"), false)
  Extensions.set_enabled("cube", true)
  eq(Extensions.get("cube") ~= nil, true)
end)

current = "math"
test("renders common inline math", function()
  local Math = require("notebook.math")
  eq(Math.render("E = mc^2"), "E = mc²")
  eq(Math.render("\\alpha + \\beta = \\pi"), "α + β = π")
  eq(Math.render("\\frac{1}{2}"), "(1)/(2)")
  eq(Math.inline("energy $E = mc^2$"), "energy E = mc²")
end)
test("splits markdown into body and math segments", function()
  local Math = require("notebook.math")
  local segments = Math.segments("E $x^2$ end")
  eq(#segments, 3)
  eq(segments[1].text, "E ")
  eq(segments[2].math, true)
  eq(segments[2].text, "x²")
  eq(segments[3].text, " end")
end)
test("lays out a display fraction", function()
  local Math = require("notebook.math")
  local fraction = Math.display_fraction("$$\\frac{a}{b}$$")
  eq(fraction.kind, "frac")
  eq(fraction.numerator.text, "a")
  eq(fraction.denominator.text, "b")
  eq(Math.display_fraction("$$x$$"), nil)
  local nested = Math.display_fraction("$$\\frac{1}{\\frac{a}{b}}$$")
  eq(nested.denominator.kind, "frac")
  eq(nested.denominator.numerator.text, "a")
end)
test("recognizes display matrices", function()
  local Math = require("notebook.math")
  local matrix = Math.display_matrix(
    "$$\\begin{matrix}a & b \\\\ c & d\\end{matrix}$$")
  eq(#matrix, 2)
  eq(matrix[1][2], "b")
  eq(matrix[2][2], "d")
  eq(Math.display_matrix("$$x$$"), nil)
end)
test("recognizes display roots", function()
  local Math = require("notebook.math")
  eq(Math.display_root("$$\\sqrt{x}$$"), "x")
  eq(Math.display_root("$$x$$"), nil)
end)
test("recognizes display math", function()
  local Math = require("notebook.math")
  eq(Math.display("$$E = mc^2$$"), "E = mc²")
  eq(Math.display("not math"), nil)
end)
test("collapses markdown headings", function()
  local Notebook = require("notebook.model")
  local cell = { kind = "markdown", source = "## Details" }
  eq(Notebook.heading_level(cell), 2)
  local notebook = Notebook.new({ cells = { cell, { kind = "code", source = "x" } } })
  eq(notebook:toggle_collapsed(1), true)
  eq(notebook.cells[1].collapsed, true)
end)

current = "outline"
test("lists heading cells and levels", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "# First\nbody" },
    { kind = "code", source = "x" },
    { kind = "markdown", source = "## Second" },
  } })
  local headings = notebook:headings()
  eq(#headings, 2)
  eq(headings[1].level, 1)
  eq(headings[1].text, "First")
  eq(headings[2].index, 3)
end)

current = "vim model"
test("deletes and inserts cells", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "one" },
    { kind = "code", source = "two" },
  } })
  local copy = notebook:copy_cell(2)
  assert(copy)
  notebook:delete_cell(2)
  eq(#notebook.cells, 1)
  notebook:insert_cell(2, copy)
  eq(notebook.cells[2].source, "two")
end)

current = "undo"
test("undoes and redoes text and cell edits", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = { { kind = "code", source = "" } } })
  notebook:insert("abc")
  eq(notebook.cells[1].source, "abc")
  notebook:undo()
  eq(notebook.cells[1].source, "")
  notebook:redo()
  eq(notebook.cells[1].source, "abc")
  notebook:add_cell("code")
  eq(#notebook.cells, 2)
  notebook:undo()
  eq(#notebook.cells, 1)
end)

current = "vim line operations"
test("matches brackets", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "local a = (1 + 2)" },
  } })
  eq(notebook:matching_bracket(11), 17)
  eq(notebook:matching_bracket(17), 11)
end)

current = "notebook title"
test("derives the title from the first level-one markdown heading", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ name = "welcome.luanb", cells = {
    { kind = "code", source = "print(1)" },
    { kind = "markdown", source = "# A 3D notebook\nbody" },
    { kind = "markdown", source = "# Second title" },
  } })
  eq(notebook:title(), "A 3D notebook")
  notebook.cells[2].source = "## Not a title"
  eq(notebook:title(), "Second title")
end)

current = "undo tree"
test("preserves branches after undo and edit", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = { { kind = "code", source = "" } } })
  notebook:insert("a")
  notebook:undo()
  notebook:insert("b")
  notebook:flush_history()
  local nodes = notebook:history_nodes_flat()
  assert(#nodes >= 3, #nodes)
  notebook:undo()
  eq(notebook.cells[1].source, "")
  notebook:redo()
  eq(notebook.cells[1].source, "b")
  local target
  for _, item in ipairs(nodes) do
    if item.node.label == "insert text" then target = item.node.id; break end
  end
  assert(notebook:restore_history(target))
  eq(notebook.cells[1].source, "a")
end)

current = "insertion"
test("adds a cell after the focused cell", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "a" },
    { kind = "code", source = "b" },
    { kind = "code", source = "c" },
  } })
  notebook:select(2)
  notebook:add_cell("code")
  eq(#notebook.cells, 4)
  eq(notebook.cells[3].source, "")
  eq(notebook.cells[4].source, "c")
  eq(notebook.active, 3)
end)

current = "vim word objects"
test("finds inner and around word ranges", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "alpha beta gamma" },
  } })
  notebook:selected().cursor = 8
  local first, last = notebook:word_range(true)
  eq(first, 7)
  eq(last, 11)
  notebook:delete_range(first, last + 1)
  eq(notebook:selected().source, "alpha gamma")
end)

current = "markdown editing"
test("edits markdown cells", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "hello" },
  } })
  notebook:selected().cursor = 6
  notebook:insert("!")
  eq(notebook:selected().source, "hello!")
  eq(notebook:selected().cursor, 7)
  notebook:backspace()
  eq(notebook:selected().source, "hello")
  notebook:cursor_home()
  eq(notebook:selected().cursor, 1)
end)

current = "vim delimiter objects"
test("finds quoted and bracketed ranges", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = 'print("hello world")' },
  } })
  notebook:selected().cursor = 10
  local first, last = notebook:delimiter_range('"', '"', false)
  eq(first, 8)
  eq(last, 18)
  notebook:selected().cursor = 14
  local bfirst, blast = notebook:delimiter_range("(", ")", true)
  eq(bfirst, 6)
  eq(blast, 20)
end)

current = "cell ops"
test("inserts above and converts cell kinds", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "a" },
    { kind = "code", source = "b" },
  } })
  notebook:select(2)
  notebook:add_cell_above("markdown")
  eq(notebook.active, 2)
  eq(notebook.cells[2].kind, "markdown")
  eq(notebook.cells[3].source, "b")
  eq(notebook:set_cell_kind(2, "code"), true)
  eq(notebook.cells[2].kind, "code")
end)

current = "extension permissions"
test("extension permissions are validated and gate the sandbox", function()
  local Manifest = require("extensions.manifest")
  local ok, err = Manifest.validate({
    id = "x", render = function() end, permissions = { "graphics" },
  })
  assert(ok ~= nil)
  ok, err = Manifest.validate({
    id = "x", render = function() end, permissions = { "network", "root" },
  })
  assert(ok == nil and tostring(err):find("invalid permission"))
  local Sandbox = require("ui.extension_sandbox")
  local env = Sandbox.create({ graphics = {}, timer = {}, input = {} },
    { "graphics" })
  assert(env.lovr.graphics ~= nil)
  assert(env.lovr.timer == nil)
end)

current = "extension permission overrides"
test("stores per-extension permission overrides", function()
  local Extensions = require("extensions")
  Extensions.registry = { demo = { id = "demo", title = "Demo",
    permissions = { "graphics", "timer" } } }
  Extensions.order = { "demo" }
  Extensions.disabled = {}
  Extensions.permission_overrides = {}
  assert(Extensions.set_permission("demo", "timer", false))
  local permissions = Extensions.permissions("demo")
  assert(#permissions == 1 and permissions[1] == "graphics")
  local listed = Extensions.list()[1]
  assert(#listed.permissions == 1)
end)

current = "vim character deletion"
test("deletes the character at or before the cursor", function()
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "abcdef" },
  } })
  notebook:selected().cursor = 3
  assert(notebook:delete_character(true))
  eq(notebook:selected().source, "abdef")
  assert(notebook:delete_character(false))
  eq(notebook:selected().source, "adef")
  eq(notebook:selected().cursor, 2)
end)

current = "markdown export"
test("exports markdown and code blocks", function()
  local notebook = Notebook.new({ name = "export-test", cells = {
    { kind = "markdown", source = "# Heading" },
    { kind = "code", source = "print(1)", output = "1" },
  } })
  local text = Format.to_markdown(notebook)
  assert(text:find("# Heading", 1, true))
  assert(text:find("```lua", 1, true))
  assert(text:find("> 1", 1, true))
end)

current = "html export"
test("exports escaped standalone HTML", function()
  local notebook = Notebook.new({ name = "html-test", cells = {
    { kind = "code", source = "print('<tag>')" },
  } })
  local text = Format.to_html(notebook)
  assert(text:find("<!doctype html>", 1, true))
  assert(text:find("&lt;tag&gt;", 1, true))
end)

current = "duplicate cell"
test("duplicates a cell with a fresh id", function()
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "print(1)" },
  } })
  local original = notebook:selected().id
  local copy = notebook:duplicate(1)
  assert(copy.id and copy.id ~= original)
  eq(#notebook.cells, 2)
  eq(notebook.active, 2)
end)

io.write(string.format("\n\n%d tests, %d passed, %d failed\n", passed + failed,
  passed, failed))
if failed > 0 then
  for _, failure in ipairs(failures) do io.write("\n" .. failure .. "\n") end
  os.exit(1)
end
