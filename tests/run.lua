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
test("loads and saves an explicit path", function()
  local path = os.tmpname()
  local notebook = Notebook.new({ name = "explicit.luanb",
    cells = { { kind = "code", source = "print('path')" } } })
  local saved = Format.save_path(notebook, path)
  eq(saved, path)
  local loaded = Format.load_path(path)
  eq(loaded.name, "explicit.luanb")
  eq(loaded._path, path)
  local invalid = os.tmpname()
  local handle = io.open(invalid, "wb"); handle:write(""); handle:close()
  local bad, err = Format.load_path(invalid)
  assert(bad == nil and err ~= nil)
  os.remove(invalid)
  os.remove(path)
end)

current = "model"
test("demo has two notebooks and a live polar cell", function()
  local notebooks = Notebook.demo()
  eq(#notebooks, 2)
  eq(#notebooks[1].cells, 24)
  local polar, field, large, quiver, stream
  for _, cell in ipairs(notebooks[1].cells) do
    if cell.source:find('orientation = "polar"', 1, true) then
      polar = polar or cell
    end
    if cell.source:find("heatmaps =", 1, true) then
      field = cell
    end
    if cell.source:find("large polar heatmap", 1, true) then
      large = cell
    end
    if cell.source:find('kind = "quiver"', 1, true) then
      quiver = cell
    end
    if cell.source:find('kind = "streamplot"', 1, true) then
      stream = cell
    end
  end
  assert(polar ~= nil, "demo is missing a polar scene cell")
  assert(field ~= nil, "demo is missing a polar field scene cell")
  assert(large ~= nil, "demo is missing a large polar heatmap cell")
  assert(quiver ~= nil, "demo is missing a polar quiver cell")
  assert(stream ~= nil, "demo is missing a polar streamplot cell")
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
test("stores execution elapsed seconds", function()
  local notebook = Notebook.new({ cells = { { kind = "code", source = "" } } })
  notebook:set_result(1, { ok = true, output = "", elapsed = 0.0125 })
  eq(notebook.cells[1].elapsed, 0.0125)
  notebook:set_result(1, { ok = false, output = "", value = "boom" })
  eq(notebook.cells[1].elapsed, nil)
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

test("filters outline headings by case-insensitive text", function()
  local Format = require("notebook.format")
  local headings = {
    { index = 1, level = 1, text = "Introduction" },
    { index = 3, level = 2, text = "Plot setup" },
    { index = 5, level = 2, text = "plot results" },
  }
  eq(#Format.filter_headings(headings, ""), 3)
  local matched = Format.filter_headings(headings, "PLOT")
  eq(#matched, 2)
  eq(matched[1].index, 3)
  eq(matched[2].index, 5)
  eq(#Format.filter_headings(headings, "missing"), 0)
end)

test("filters tag-index entries by case-insensitive tag name", function()
  local Format = require("notebook.format")
  local entries = {
    { tag = "lua", count = 3 }, { tag = "plots", count = 2 },
    { tag = "notebook", count = 1 },
  }
  eq(#Format.filter_tag_entries(entries, ""), 3)
  local matched = Format.filter_tag_entries(entries, "L")
  eq(#matched, 2)
  eq(matched[1].tag, "lua")
  eq(matched[2].tag, "plots")
  eq(#Format.filter_tag_entries(entries, "zzz"), 0)
end)

test("navigates between headings without wrapping", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "# First" },
    { kind = "code", source = "x" },
    { kind = "markdown", source = "## Second" },
    { kind = "markdown", source = "### Third" },
  } })
  notebook:select(1)
  eq(notebook:heading_relative(1), 3)
  notebook:select(3)
  eq(notebook:heading_relative(1), 4)
  notebook:select(4)
  eq(notebook:heading_relative(1), nil)
  eq(notebook:heading_relative(-1), 3)
  notebook:select(1)
  eq(notebook:heading_relative(-1), nil)
end)
test("collapses and expands every heading as one edit", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "# First" },
    { kind = "markdown", source = "## Second" },
    { kind = "code", source = "x" },
  } })
  notebook.cells[2].collapsed = true
  eq(notebook:set_headings_collapsed(true), true)
  eq(notebook:set_headings_collapsed(true), false)
  eq(notebook.cells[1].collapsed, true)
  eq(notebook.cells[2].collapsed, true)
  eq(notebook.cells[3].collapsed == true, false)
  eq(notebook.dirty, true)
  eq(notebook:set_headings_collapsed(false), true)
  eq(notebook.cells[1].collapsed, false)
  eq(notebook.cells[2].collapsed, false)
end)
test("undoes and redoes a bulk heading fold", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "# First" },
    { kind = "markdown", source = "## Second" },
  } })
  notebook.cells[1].collapsed = true
  notebook:reset_history()
  eq(notebook:set_headings_collapsed(true), true)
  notebook:undo()
  eq(notebook.cells[1].collapsed, true)
  eq(notebook.cells[2].collapsed == true, false)
  notebook:redo()
  eq(notebook.cells[1].collapsed, true)
  eq(notebook.cells[2].collapsed, true)
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

test("renames the existing title or inserts a heading", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "# Old\nbody" },
  } })
  eq(notebook:set_title("New"), true)
  eq(notebook.cells[1].source, "# New\nbody")
  eq(notebook:title(), "New")
  eq(notebook:set_title("New"), false)
  eq(notebook:set_title(""), false)
  notebook.cells[1].source = "prose only"
  eq(notebook:set_title("Inserted"), true)
  eq(notebook.cells[1].kind, "markdown")
  eq(notebook.cells[1].source, "# Inserted")
  eq(notebook.active, 1)
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
test("toggles one Markdown task marker without changing the rest", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "- [ ] first\n  * [x] second\nplain" },
  } })
  eq(notebook:toggle_task(1, 1), true)
  eq(notebook.cells[1].source,
    "- [x] first\n  * [x] second\nplain")
  eq(notebook.dirty, true)
  eq(notebook:toggle_task(1, 2), false)
  eq(notebook.cells[1].source,
    "- [x] first\n  * [ ] second\nplain")
  eq(notebook:toggle_task(1, 3), nil)
  eq(notebook:toggle_task(2, 1), nil)
  notebook:undo()
  eq(notebook.cells[1].source,
    "- [x] first\n  * [x] second\nplain")
end)

current = "line editing"
test("moves, duplicates, comments, indents, and seeks source lines", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "one\ntwo\nthree" },
  } })
  local cell = notebook.cells[1]
  cell.cursor = 6
  eq(notebook:shift_line(-1), true)
  eq(cell.source, "two\none\nthree")
  eq(cell.cursor, 2)
  eq(notebook:shift_line(-1), false)

  cell.source = "one\ntwo"
  cell.cursor = 6
  eq(notebook:duplicate_line(), true)
  eq(cell.source, "one\ntwo\ntwo")
  eq(cell.cursor, 10)

  cell.source = "  value = 1"
  cell.cursor = 5
  eq(notebook:toggle_comment(), true)
  eq(cell.source, "  -- value = 1")
  eq(notebook:toggle_comment(), true)
  eq(cell.source, "  value = 1")

  cell.source = "line"
  cell.cursor = 3
  eq(notebook:indent_line(1), true)
  eq(cell.source, "  line")
  eq(notebook:indent_line(-1), true)
  eq(cell.source, "line")

  cell.source = "first\nsecond\nthird"
  eq(notebook:go_to_line(3), true)
  eq(cell.cursor, 14)
  eq(notebook:go_to_line(4), false)
  cell.kind = "markdown"
  eq(notebook:toggle_comment(), false)
end)

test("moves and deletes by word and joins lines", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "alpha beta gamma" },
  } })
  local cell = notebook.cells[1]
  cell.cursor = 1
  eq(notebook:move_word(1), true)
  eq(cell.cursor, 7)
  eq(notebook:move_word(1), true)
  eq(cell.cursor, 12)
  eq(notebook:move_word(-1), true)
  eq(cell.cursor, 7)

  cell.cursor = #cell.source + 1
  eq(notebook:delete_word(-1), true)
  eq(cell.source, "alpha beta ")
  cell.cursor = 1
  eq(notebook:delete_word(1), true)
  eq(cell.source, "beta ")

  cell.source = "alpha\n  beta"
  cell.cursor = 3
  eq(notebook:join_line(), true)
  eq(cell.source, "alpha beta")
  eq(cell.cursor, 7)
  cell.source = "a\nb\nc"
  eq(notebook:cursor_cell_start(), true)
  eq(cell.cursor, 1)
  eq(notebook:cursor_cell_end(), true)
  eq(cell.cursor, #cell.source + 1)
end)

test("toggles inline Markdown formatting around the current word", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "alpha beta" },
  } })
  local cell = notebook.cells[1]
  cell.cursor = 3
  eq(notebook:toggle_inline("**", "**", "bold"), true)
  eq(cell.source, "**alpha** beta")
  eq(cell.cursor, 5)
  eq(notebook:toggle_inline("**", "**", "bold"), true)
  eq(cell.source, "alpha beta")
  eq(cell.cursor, 3)
  cell.cursor = 8
  eq(notebook:toggle_inline("*", "*", "italic"), true)
  eq(cell.source, "alpha *beta*")
  cell.cursor = 1
  eq(notebook:toggle_inline("`", "`", "code"), true)
  assert(cell.source:find("`alpha`", 1, true) == 1)
  cell.cursor = 1
  eq(notebook:toggle_inline("==", "==", "highlight"), true)
  assert(cell.source:find("==`alpha`==", 1, true) == 1)
  cell.cursor = 1
  eq(notebook:toggle_inline("~~", "~~", "strike"), true)
  assert(cell.source:find("~~==`alpha`==~~", 1, true) == 1)
  cell.kind = "code"
  eq(notebook:toggle_inline("**", "**", "bold"), false)
end)

test("toggles Markdown block prefixes and heading levels", function()
  local Notebook = require("notebook.model")
  local notebook = Notebook.new({ cells = {
    { kind = "markdown", source = "text" },
  } })
  local cell = notebook.cells[1]
  cell.cursor = 2
  eq(notebook:toggle_block("quote"), true)
  eq(cell.source, "> text")
  eq(notebook:toggle_block("quote"), true)
  eq(cell.source, "text")
  eq(notebook:toggle_block("bullet"), true)
  eq(cell.source, "- text")
  eq(notebook:toggle_block("bullet"), true)
  eq(cell.source, "text")
  eq(notebook:toggle_block("ordered"), true)
  eq(cell.source, "1. text")
  eq(notebook:toggle_block("ordered"), true)
  eq(cell.source, "text")
  eq(notebook:cycle_heading(), true)
  eq(cell.source, "# text")
  eq(notebook:cycle_heading(), true)
  eq(cell.source, "## text")
  eq(notebook:cycle_heading(), true)
  eq(cell.source, "### text")
  eq(notebook:cycle_heading(), true)
  eq(cell.source, "text")
  cell.cursor = 2
  eq(notebook:insert_link("https://example.test"), true)
  eq(cell.source, "[text](https://example.test)")
  eq(notebook:insert_link(""), false)
  cell.kind = "code"
  eq(notebook:toggle_block("quote"), false)
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
    { kind = "markdown", source = "# Heading" },
    { kind = "code", source = "print('<tag>')" },
  } })
  local text = Format.to_html(notebook)
  assert(text:find("<!doctype html>", 1, true))
  assert(text:find("&lt;tag&gt;", 1, true))
  assert(text:find(
    '<h1 id="heading">Heading<a class="heading-permalink" href="#heading"',
    1, true))
end)

test("exports footnote references and endnotes", function()
  local notebook = Notebook.new({ name = "footnotes.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "Alpha[^a] and beta[^b].",
      "",
      "[^a]: first *note*",
      "[^b]: second note",
      "",
      "Undefined[^missing] and \\[^escaped].",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find(
    '<sup class="footnote-ref" id="fnref-cell-1-1"><a href="#fn-cell-1-1">1</a></sup>',
    1, true))
  assert(html:find(
    '<sup class="footnote-ref" id="fnref-cell-1-2"><a href="#fn-cell-1-2">2</a></sup>',
    1, true))
  assert(html:find('<section class="footnotes" role="doc-endnotes">', 1, true))
  assert(html:find('<li id="fn-cell-1-1">first <em>note</em> ', 1, true))
  assert(html:find('<li id="fn-cell-1-2">second note ', 1, true))
  assert(html:find('class="footnote-back" href="#fnref-cell-1-1"', 1, true))
  assert(html:find("[^missing]", 1, true))
  assert(html:find("[^escaped]", 1, true))
  assert(not html:find("<p>[^a]: first", 1, true))
end)

current = "html navigation"
test("builds deterministic heading anchors and table of contents", function()
  local notebook = Notebook.new({ name = "nav.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "# Intro",
      "",
      "```lua",
      "# not a heading",
      "```",
      "",
      "# Intro",
      "",
      "## **Bold** `plot` section",
    }, "\n") },
    { kind = "code", source = "return { scene = 'cube' }" },
  } })
  notebook.cells[2].scene = "cube"
  local headings = Format.headings(notebook.cells)
  eq(#headings, 3)
  eq(headings[1].id, "intro")
  eq(headings[1].level, 1)
  eq(headings[2].id, "intro-2")
  eq(headings[3].text, "Bold plot section")
  eq(headings[3].id, "bold-plot-section")
  eq(headings[3].cell, 1)
  local html = Format.to_html(notebook)
  assert(html:find('<nav class="toc"', 1, true))
  assert(html:find('href="#intro-2"', 1, true))
  assert(html:find('id="bold-plot-section"', 1, true))
  assert(html:find(
    'class="heading-permalink" href="#bold-plot-section"', 1, true))
  assert(html:find(
    'aria-label="Permalink to Bold plot section"', 1, true))
  assert(html:find('id="cell-1"', 1, true))
  assert(html:find('name="viewport"', 1, true))
  assert(html:find('name="generator"', 1, true))
  assert(html:find("Figure 1: Cell 2", 1, true))
  assert(html:find('id="not-a-heading"', 1, true) == nil)
  eq(Format.to_html(notebook), html)
end)

current = "html search"
test("renders search controls and a searchable cell index", function()
  local notebook = Notebook.new({ name = "search.luanb", cells = {
    { kind = "markdown", source =
      "# Intro\n\nQuick   brown fox. See [docs](https://example.com/secret)." },
    { kind = "code", source = "print('needle')", output = "haystack value" },
  } })
  local prose = Format.search_text(notebook.cells[1])
  assert(prose:find("Quick brown fox", 1, true))
  assert(prose:find("docs", 1, true))
  assert(prose:find("secret", 1, true) == nil)
  local code = Format.search_text(notebook.cells[2])
  assert(code:find("needle", 1, true))
  assert(code:find("haystack", 1, true))
  eq(Format.search_text(nil), "")
  local html = Format.to_html(notebook)
  assert(html:find('<html lang="en" class="no-js">', 1, true))
  assert(html:find('id="search-input"', 1, true))
  assert(html:find('<option value="figures">Figure cells</option>', 1, true))
  assert(html:find('data-search="', 1, true))
  assert(html:find('data-cell="1"', 1, true))
  assert(html:find("URLSearchParams", 1, true))
  eq(Format.to_html(notebook), html)
end)

test("escapes search attributes and flags figure cells", function()
  local notebook = Notebook.new({ name = "search-escape.luanb", cells = {
    { kind = "code", source = 'print("a & b <tag>")' },
  } })
  notebook.cells[1].scene = "cube"
  notebook.cells[1].widgets = {
    { kind = "slider", label = 'volume "up"' },
  }
  local html = Format.to_html(notebook)
  assert(html:find(
    'data-search="print(&quot;a &amp; b &lt;tag&gt;&quot;)', 1, true))
  assert(html:find('data-has-scene="true"', 1, true))
  assert(html:find("extension scene · cube", 1, true))
end)

current = "html task lists"
test("renders Markdown checklists as disabled task items", function()
  local notebook = Notebook.new({ name = "tasks.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "## Checklist",
      "",
      "- [x] shipped **export**",
      "- [ ] write `docs`",
      "- plain item",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find('<ul class="task-list">', 1, true))
  assert(html:find('<li class="task-list-item done"><input type="checkbox" disabled checked> shipped <strong>export</strong></li>', 1, true))
  assert(html:find('<li class="task-list-item"><input type="checkbox" disabled> write <code>docs</code></li>', 1, true))
  assert(html:find('<li>plain item</li>', 1, true))
  eq(select(2, html:gsub('class="task%-list%-item', "")), 2)
end)

current = "html markdown rules"
test("renders horizontal rules and strikethrough", function()
  local notebook = Notebook.new({ name = "rules.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "Before",
      "",
      "---",
      "",
      "Retired ~~old~~ text.",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find("<p>Before</p>", 1, true))
  assert(html:find("<hr>", 1, true))
  assert(html:find("<p>Retired <del>old</del> text.</p>", 1, true))
  assert(html:find("<p>----------</p>", 1, true) == nil)
end)

test("renders nested Markdown blockquotes", function()
  local notebook = Notebook.new({ name = "quotes.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "> outer",
      "> > inner",
      "> outer again",
      "> > > deepest",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find(
    "<blockquote><p>outer</p><blockquote><p>inner</p></blockquote>" ..
    "<p>outer again</p><blockquote><blockquote>" ..
    "<p>deepest</p></blockquote></blockquote></blockquote>", 1, true))
end)

test("renders GitHub-style callout blockquotes", function()
  local notebook = Notebook.new({ name = "callouts.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "> [!WARNING]",
      "> Careful with **this**.",
      ">",
      "> Second paragraph.",
      "",
      "> [!UNKNOWN]",
      "> Not a callout.",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find(
    '<div class="callout callout-warning"><p class="callout-title">' ..
    'Warning</p><p>Careful with <strong>this</strong>.</p>' ..
    '<p>Second paragraph.</p></div>', 1, true))
  assert(html:find('<div class="callout callout-unknown">', 1, true) == nil)
  assert(html:find("<p>[!UNKNOWN]</p>", 1, true))
end)

test("renders Markdown definition lists", function()
  local notebook = Notebook.new({ name = "definitions.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "Alpha",
      ": first **term**",
      "Beta",
      ": second term",
      "",
      "Normal paragraph.",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find(
    "<dl><dt>Alpha</dt><dd>first <strong>term</strong></dd>" ..
    "<dt>Beta</dt><dd>second term</dd></dl>", 1, true))
  assert(html:find("<p>Normal paragraph.</p>", 1, true))
end)

current = "html ordered lists"
test("preserves an ordered list's start number and parenthesis markers", function()
  local notebook = Notebook.new({ name = "ordered.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "Steps:",
      "",
      "3) third",
      "4) fourth",
      "",
      "1. one",
      "2. two",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find('<ol start="3"><li>third</li><li>fourth</li></ol>', 1,
    true))
  assert(html:find("<ol><li>one</li><li>two</li></ol>", 1, true))
end)

current = "html markdown tables"
test("renders pipe tables with alignment and inline formatting", function()
  local notebook = Notebook.new({ name = "tables.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "| Item | Value |",
      "| :--- | ---: |",
      "| alpha | **1** |",
      "| beta | `2` |",
      "",
      "After",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find('<table class="markdown-table"><thead><tr><th>Item</th>' ..
    '<th class="align-right">Value</th></tr></thead><tbody>', 1, true))
  assert(html:find('<tr><td>alpha</td><td class="align-right">' ..
    '<strong>1</strong></td></tr>', 1, true))
  assert(html:find('<tr><td>beta</td><td class="align-right">' ..
    '<code>2</code></td></tr>', 1, true))
  assert(html:find("</tbody></table>\n<p>After</p>", 1, true))
  local fenced = Notebook.new({ name = "fenced.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "```lua",
      "| a | b |",
      "| --- | --- |",
      "```",
    }, "\n") },
  } })
  assert(Format.to_html(fenced):find('<table class="markdown-table">', 1,
    true) == nil)
end)

current = "html nested lists"
test("renders nested unordered, ordered, and task lists", function()
  local notebook = Notebook.new({ name = "nested.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "- one",
      "  - two",
      "    3. three",
      "- four",
      "",
      "- [x] parent",
      "  - [ ] child",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find('<ul><li>one<ul><li>two<ol start="3">' ..
    '<li>three</li></ol></li></ul></li><li>four</li></ul>', 1, true))
  assert(html:find('<ul class="task-list"><li class="task-list-item done">' ..
    '<input type="checkbox" disabled checked> parent<ul class="task-list">' ..
    '<li class="task-list-item"><input type="checkbox" disabled> child' ..
    '</li></ul></li></ul>', 1, true))
end)

current = "html emphasis and quotes"
test("renders inline emphasis and groups quote lines", function()
  local notebook = Notebook.new({ name = "emphasis.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "*italic* _under_ __bold__ **strong** and `*literal*`",
      "",
      "> q1",
      "> q2",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find('<p><em>italic</em> <em>under</em> ' ..
    '<strong>bold</strong> <strong>strong</strong> and ' ..
    '<code>*literal*</code></p>', 1, true))
  assert(html:find('<blockquote><p>q1</p><p>q2</p></blockquote>', 1, true))
  local identifiers = Notebook.new({ name = "ids.luanb", cells = {
    { kind = "markdown", source = "snake_case_name stays literal" },
  } })
  assert(Format.to_html(identifiers):find("snake_case_name stays literal",
    1, true))
end)

current = "html inline extensions"
test("renders highlights, autolinks, and backslash escapes", function()
  local notebook = Notebook.new({ name = "inline.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "==marked== and https://example.com/docs.",
      "",
      "\\*literal\\* and \\[brackets\\] and \\\\",
      "",
      "`https://example.com` and [https://example.com](https://example.com)",
    }, "\n") },
  } })
  local html = Format.to_html(notebook)
  assert(html:find('<mark>marked</mark>', 1, true))
  assert(html:find('<a href="https://example.com/docs" ' ..
    'rel="noopener noreferrer">https://example.com/docs</a>.', 1, true))
  assert(html:find('<p>*literal* and [brackets] and \\</p>', 1, true))
  assert(html:find('<code>https://example.com</code>', 1, true))
  local body = html:match('<main id="content">(.-)</main>')
  local _, anchors = body:gsub('<a href="https://', "")
  eq(anchors, 2)
  assert(html:find('<a href="https://example.com" ' ..
    'rel="noopener noreferrer">https://example.com</a>', 1, true))
end)

current = "html code blocks"
test("renders labeled, numbered code blocks with copy controls", function()
  local notebook = Notebook.new({ name = "code.luanb", cells = {
    { kind = "markdown", source = table.concat({
      "```lua",
      "print('<tag>')",
      "return 1",
      "```",
    }, "\n") },
    { kind = "code", source = "local a = 1\nreturn a" },
  } })
  local html = Format.to_html(notebook)
  assert(html:find('<div class="code-block">', 1, true))
  assert(html:find('<span class="code-lang">lua</span>', 1, true))
  assert(html:find('class="copy-code"', 1, true))
  assert(html:find(
    '<span class="code-line" data-line="1">print(&#39;&lt;tag&gt;&#39;)</span>',
    1, true))
  assert(html:find("&lt;tag&gt;", 1, true))
  assert(html:find("&amp;lt;tag&amp;gt;", 1, true) == nil)
  assert(html:find(
    '<span class="code-line" data-line="1">local a = 1</span>' ..
    '<span class="code-line" data-line="2">return a</span>', 1, true))
  assert(html:find("textFor", 1, true))
  eq(select(2, html:gsub('class="code%-block"', "")), 2)
end)

current = "html figures"
test("renders scene and widget placeholders", function()
  local notebook = Notebook.new({ name = "fig.luanb", cells = {
    { kind = "code", source = "return { scene = plot }" },
    { kind = "code", source = "widgets.slider({ label = 'gain' })" },
  } })
  notebook.cells[1].scene = {
    type = "luaplotlib", title = "sin <x>", xlim = { 0, 2 },
    ylim = { -1, 1 }, grid = true,
    series = {
      { kind = "line", x = { 0, 1, 2 }, y = { 0, 1, 0 },
        style = { color = "#1f77b4" } },
      { kind = "scatter", x = { 1, 2 }, y = { 0.5, 0.5 } },
    },
  }
  notebook.cells[2].widgets = {
    { kind = "slider", label = "gain" },
    { kind = "button", label = "Ping" },
  }
  local summary = Format.scene_summary(notebook.cells[1].scene)
  eq(summary.kind, "luaplotlib")
  eq(summary.count, 2)
  eq(summary.points, 5)
  local svg = Format.scene_svg(notebook.cells[1].scene)
  assert(svg:find("<polyline", 1, true))
  assert(svg:find("<circle", 1, true))
  local html = Format.to_html(notebook)
  assert(html:find('class="scene"', 1, true))
  assert(html:find("<figcaption>", 1, true))
  assert(html:find("sin &lt;x&gt;", 1, true))
  assert(html:find("Scene data", 1, true))
  assert(html:find("Interactive widgets", 1, true))
  assert(html:find("slider — gain", 1, true))
  assert(html:find('id="figure-1"', 1, true))
  eq(Format.scene_summary({ type = "luaplotlib", series = {
    { kind = "bar", x = { 1, 2 }, y = { 3, 4 } },
  } }).points, 2)
  eq(Format.scene_summary("cube").kind, "extension")
  assert(Format.scene_svg("cube"):find("<polygon", 1, true))
  eq(Format.scene_svg(nil), nil)
end)

current = "html polar"
test("summarizes and previews polar scenes", function()
  local notebook = Notebook.new({ name = "polar.luanb", cells = {
    { kind = "code", source = "return { scene = polar_plot }" },
  } })
  notebook.cells[1].scene = {
    type = "luaplotlib", orientation = "polar", title = "rose <r>",
    theta_zero = math.pi / 2, theta_direction = "clockwise",
    polar = {
      theta_zero = math.pi / 2,
      theta_direction = "clockwise",
      rmax = 2,
      theta_ticks = {
        { value = 0, degrees = 0, label = "E" },
        { value = math.pi / 2, degrees = 90, label = "<N>" },
      },
      r_ticks = { { value = 1, label = "1" }, { value = 2, label = "2" } },
      series = {
        { kind = "line", theta = { 0, math.pi / 2, math.pi },
          r = { 1, 2, 1 },
          style = { color = "#1f77b4", label = "spiral" } },
        { kind = "scatter", theta = { 0 }, r = { 1 },
          style = { color = "#ff7f0e", radius = 4 } },
        { kind = "bar", theta = { math.pi }, r = { 1.5 },
          widths = { 0.4 }, colors = { "#2ca02c" } },
      },
    },
  }
  local summary = Format.scene_summary(notebook.cells[1].scene)
  eq(summary.kind, "luaplotlib")
  eq(summary.orientation, "polar")
  eq(summary.count, 3)
  eq(summary.points, 5)
  local svg = Format.scene_svg(notebook.cells[1].scene)
  assert(svg:find('class="scene-polar"', 1, true))
  assert(svg:find('data-theta-direction="clockwise"', 1, true))
  assert(svg:find("scene-polar-spoke", 1, true))
  assert(svg:find("scene-polar-ring", 1, true))
  assert(svg:find("<polyline", 1, true))
  assert(svg:find("scene-polar-point", 1, true))
  assert(svg:find("scene-polar-bar", 1, true))
  assert(svg:find("&lt;N&gt;", 1, true))
  local html = Format.to_html(notebook)
  assert(html:find('data-orientation="polar"', 1, true))
  assert(html:find("polar · line, scatter, bar · 3 series · 5 points",
    1, true))
  assert(html:find("rose &lt;r&gt;", 1, true))
  local indexed = Format.search_text(notebook.cells[1])
  assert(indexed:find("polar", 1, true))
  assert(indexed:find("spiral", 1, true))
  eq(Format.to_html(notebook), html)
end)

test("polar preview handles empty and non-finite data", function()
  local empty = { type = "luaplotlib", orientation = "polar", polar = {} }
  local summary = Format.scene_summary(empty)
  eq(summary.orientation, "polar")
  eq(summary.count, 0)
  eq(summary.points, 0)
  local svg = Format.scene_svg(empty)
  assert(svg:find("scene-polar-frame", 1, true))
  assert(svg:find("scene-polar-spoke", 1, true))
  local bad = {
    type = "luaplotlib", orientation = "polar",
    polar = {
      rmax = 0,
      series = {
        { kind = "line", theta = { 0, 1 / 0, 2 }, r = { 1, 2, 0 / 0 } },
      },
    },
  }
  local bad_svg = Format.scene_svg(bad)
  assert(bad_svg:find('data-rmax="', 1, true))
  assert(bad_svg:find("nan", 1, true) == nil)
  assert(bad_svg:find("inf", 1, true) == nil)
end)

current = "html escaping"
test("escapes scene metadata and limits scene JSON", function()
  local notebook = Notebook.new({ name = "escape.luanb", cells = {
    { kind = "code", source = "return scene" },
    { kind = "markdown", source =
      "[ok](https://example.com/a?b=1&c=2) " ..
      "[bad](javascript:alert(1)) [mail](mailto:a@example.com)" },
  } })
  notebook.cells[1].scene = {
    type = "luaplotlib", title = '<script>alert("x")</script>', series = {},
  }
  local html = Format.to_html(notebook)
  assert(html:find("<script>alert", 1, true) == nil)
  assert(html:find("&lt;script&gt;alert", 1, true))
  assert(html:find('href="https://example.com/a?b=1&amp;c=2"', 1, true))
  assert(html:find("javascript:", 1, true) == nil)
  assert(html:find("mailto:a@example.com", 1, true))
  local text, truncated = Format.scene_json({ text = string.rep("a", 5000) },
    40)
  eq(truncated, true)
  assert(#text >= 40)
  local small, cut = Format.scene_json({ ok = true })
  eq(cut, false)
  assert(small:find('"ok":true', 1, true))
  eq(Format.scene_json({ bad = function() end }), nil)
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
  notebook:undo()
  eq(#notebook.cells, 1)
  eq(notebook.active, 1)
end)

current = "tag index"
test("collects markdown tags in order", function()
  local counts, order = Format.tags({
    { kind = "markdown", source = "# Heading\nTags: #lua #notebook #lua" },
    { kind = "code", source = "# not a tag" },
  })
  assert(counts.lua == 2 and counts.notebook == 1)
  assert(order[1] == "lua" and order[2] == "notebook")
end)

test("ignores tags in code, URLs, colors, and strikethrough", function()
  local counts = Format.tags({
    { kind = "markdown", source = table.concat({
      "# Heading #lua",
      "`#inline` and ``#double``",
      "```sh",
      "# fenced #hidden",
      "```",
      "See https://example.com/page#fragment",
      "Color #fff and #1a2b3c; #cafe is a color.",
      "(#paren) [#bracket] #ok.",
      "~~#strike~~",
    }, "\n") },
  })
  eq(counts.lua, 1)
  eq(counts.paren, 1)
  eq(counts.bracket, 1)
  eq(counts.ok, 1)
  eq(counts.inline, nil)
  eq(counts.double, nil)
  eq(counts.hidden, nil)
  eq(counts.fragment, nil)
  eq(counts.fff, nil)
  eq(counts.cafe, nil)
  eq(counts.strike, nil)
end)

test("aggregates tag index across open notebooks", function()
  local a = Notebook.new({ name = "a.luanb", cells = {
    { kind = "markdown", source = "#lua #tags #lua" },
    { kind = "code", source = "#lua" },
  } })
  local b = Notebook.new({ name = "b.luanb", cells = {
    { kind = "markdown", source = "#tags #plots" },
  } })
  local entries = Format.tag_index({ a, b })
  eq(#entries, 3)
  eq(entries[1].tag, "lua")
  eq(entries[1].count, 2)
  eq(#entries[1].notebooks, 1)
  eq(entries[2].tag, "tags")
  eq(entries[2].count, 2)
  eq(#entries[2].notebooks, 2)
  eq(entries[2].notebooks[2].title, "b")
  eq(entries[3].tag, "plots")
end)

current = "notebook statistics"
test("counts cells, source lines, prose, structure, and output", function()
  local notebook = Notebook.new({ name = "stats.luanb", cells = {
    { kind = "markdown", source = "# Intro\n\nTwo words.\n\n[[Other]] #tag" },
    { kind = "code", source = "print(1)\nprint(2)", output = "1\n2" },
    { kind = "code", source = "error('boom')", error = "boom" },
  } })
  local stats = Format.html_stats(notebook)
  eq(stats.cells, 3)
  eq(stats.code, 2)
  eq(stats.markdown, 1)
  eq(stats.lines, 8)
  eq(stats.code_lines, 3)
  eq(stats.markdown_lines, 5)
  eq(stats.headings, 1)
  eq(stats.links, 1)
  eq(stats.tags, 1)
  eq(stats.outputs, 1)
  eq(stats.errors, 1)
  eq(stats.words, 6)
  local html = Format.to_html(notebook)
  assert(html:find("— 3 cells, 2 code, 1 markdown", 1, true))
end)

current = "output expansion"
test("previews six long-output lines and persists expansion", function()
  local lines = {}
  for index = 1, 12 do lines[index] = "line " .. index end
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "print()", output = table.concat(lines, "\n") },
  } })
  local shown, total = Notebook.output_lines_shown(notebook.cells[1])
  eq(shown, 6)
  eq(total, 12)
  eq(notebook:toggle_output(1), true)
  shown, total = Notebook.output_lines_shown(notebook.cells[1])
  eq(shown, 12)
  eq(total, 12)
  local decoded = Format.decode(Format.encode(notebook))
  eq(decoded.cells[1].output_expanded, true)
  eq(Notebook.output_lines_shown(decoded.cells[1]), 12)
  eq(notebook:toggle_output(1), false)
  eq(select(1, Notebook.output_lines_shown(notebook.cells[1])), 6)
end)
test("expands and collapses every long output as one edit", function()
  local long = table.concat({ "1", "2", "3", "4", "5", "6", "7" }, "\n")
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "print()", output = long },
    { kind = "code", source = "print()", output = "short" },
    { kind = "code", source = "print()", output = long },
  } })
  eq(notebook:set_outputs_expanded(true), true)
  eq(notebook.cells[1].output_expanded, true)
  eq(notebook.cells[2].output_expanded == true, false)
  eq(notebook.cells[3].output_expanded, true)
  eq(notebook:set_outputs_expanded(true), false)
  eq(notebook:set_outputs_expanded(false), true)
  eq(notebook.cells[1].output_expanded, false)
  eq(notebook.cells[3].output_expanded, false)
end)
test("leaves short output unchanged and ignores missing cells", function()
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "print()", output = "one\ntwo" },
  } })
  eq(select(1, Notebook.output_lines_shown(notebook.cells[1])), 2)
  eq(Notebook.output_lines_shown(nil), 0)
  eq(notebook:toggle_output(99), false)
end)

current = "execution timing"
test("formats timing without changing the cell baseline", function()
  eq(Format.duration(0.0004), "<1 ms")
  eq(Format.duration(0.0123), "12 ms")
  eq(Format.duration(0.999), "999 ms")
  eq(Format.duration(2.5), "2.50 s")
  eq(Format.duration(90), "1.5 min")
  eq(Format.duration(nil), nil)
end)

test("sums recorded timings for the run-all status", function()
  local total, count = Format.total_elapsed({
    { elapsed = 0.1 }, { elapsed = 0.2 }, {}, { elapsed = -1 },
  })
  assert(math.abs(total - 0.3) < 1e-9, total)
  eq(count, 3)
  local none, zero = Format.total_elapsed({ {}, { elapsed = "1" } })
  eq(none, nil)
  eq(zero, 0)
end)

current = "autosave"
test("autosave paths are safe and deterministic", function()
  local notebook = Notebook.new({ name = "my notebook.luanb", cells = {} })
  eq(Format.autosave_path(notebook), "autosaves/my_notebook.luanb")
end)

current = "session"
test("session files round-trip paths and active tab", function()
  local text = Format.encode_session({ "a.luanb", "b.luanb" }, "b.luanb")
  local paths, active = Format.decode_session(text)
  eq(#paths, 2); eq(paths[1], "a.luanb"); eq(active, "b.luanb")
  local bad = Format.decode_session("not json")
  eq(bad, nil)
end)

current = "filetree"
test("filters notebook files and keeps ancestor directories", function()
  local entries = {
    { path = "notebooks/work", name = "work", kind = "directory", depth = 0 },
    { path = "notebooks/work/alpha.luanb", name = "alpha.luanb",
      kind = "file", depth = 1 },
    { path = "notebooks/work/beta.luanb", name = "beta.luanb",
      kind = "file", depth = 1 },
    { path = "notebooks/play", name = "play", kind = "directory", depth = 0 },
    { path = "notebooks/play/gamma.luanb", name = "gamma.luanb",
      kind = "file", depth = 1 },
  }
  local filtered = Format.filter_entries(entries, "ALPHA")
  eq(#filtered, 2)
  eq(filtered[1].path, "notebooks/work")
  eq(filtered[2].path, "notebooks/work/alpha.luanb")
  eq(#Format.filter_entries(entries, "missing"), 0)
  eq(#Format.filter_entries(entries, "  "), #entries)
end)
test("recursively searches collapsed folders for the filter", function()
  local saved_lovr = rawget(_G, "lovr")
  local tree = {
    notebooks = { "play", "work" },
    ["notebooks/work"] = { "alpha.luanb", "beta.luanb" },
    ["notebooks/play"] = { "gamma.luanb" },
  }
  _G.lovr = { filesystem = {
    getDirectoryItems = function(path) return tree[path] or {} end,
    isDirectory = function(path) return tree[path] ~= nil end,
  } }
  local entries = Format.list_tree({}, "notebooks", 0, true)
  _G.lovr = saved_lovr
  eq(#entries, 5)
  local filtered = Format.filter_entries(entries, "alpha")
  eq(#filtered, 2)
  eq(filtered[1].name, "work")
  eq(filtered[2].name, "alpha.luanb")
end)
test("sorts filetree entries by name and modification time", function()
  local saved_lovr = rawget(_G, "lovr")
  local tree = { notebooks = { "beta.luanb", "work", "alpha.luanb" } }
  local times = {
    ["notebooks/alpha.luanb"] = 200,
    ["notebooks/beta.luanb"] = 100,
    ["notebooks/work"] = 50,
  }
  _G.lovr = { filesystem = {
    getDirectoryItems = function(path) return tree[path] or {} end,
    isDirectory = function(path) return path == "notebooks/work" end,
    getLastModified = function(path) return times[path] end,
  } }
  local function file_names(mode)
    local names = {}
    for _, item in ipairs(Format.list_tree({}, "notebooks", 0, false, mode)) do
      if item.kind == "file" then names[#names + 1] = item.name end
    end
    return table.concat(names, ",")
  end
  eq(file_names("name"), "alpha.luanb,beta.luanb")
  eq(file_names("name-desc"), "beta.luanb,alpha.luanb")
  eq(file_names("recent"), "alpha.luanb,beta.luanb")
  _G.lovr = saved_lovr
end)

test("creates and renames folders under a parent", function()
  local saved_lovr = rawget(_G, "lovr")
  local created
  _G.lovr = { filesystem = {
    createDirectory = function(path) created = path; return true end,
    getSaveDirectory = function() return "/save" end,
    isDirectory = function() return false end,
  } }
  local path = Format.create_folder(" sub ", "notebooks/work")
  eq(path, "notebooks/work/sub")
  eq(created, path)
  eq(Format.create_folder("../bad", "notebooks/work"), nil)
  local saved_rename = os.rename
  local from, to
  os.rename = function(source, target) from, to = source, target; return true end
  local renamed = Format.rename_folder("notebooks/work/sub", "renamed")
  os.rename = saved_rename
  eq(renamed, "notebooks/work/renamed")
  eq(from, "/save/notebooks/work/sub")
  eq(to, "/save/notebooks/work/renamed")
  _G.lovr = saved_lovr
end)

test("moves, duplicates, and names notebooks in folders", function()
  local saved_lovr = rawget(_G, "lovr")
  local files = { ["notebooks/work/note.luanb"] = "{}" }
  _G.lovr = { filesystem = {
    read = function(path) return files[path] end,
    write = function(path, text) files[path] = text; return true end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/save" end,
  } }
  local path, name = Format.unique_notebook_path("notebooks/work", "note")
  eq(path, "notebooks/work/note-2.luanb")
  eq(name, "note-2.luanb")
  local saved_rename = os.rename
  local from, to
  os.rename = function(source, target) from, to = source, target; return true end
  local moved = Format.move_path("notebooks/work/note.luanb", "notebooks/other")
  os.rename = saved_rename
  eq(moved, "notebooks/other/note.luanb")
  eq(from, "/save/notebooks/work/note.luanb")
  eq(to, "/save/notebooks/other/note.luanb")
  local copy = Format.duplicate_path("notebooks/work/note.luanb")
  eq(copy, "notebooks/work/note-copy.luanb")
  eq(files[copy], "{}")
  _G.lovr = saved_lovr
end)

test("saves a notebook inside a folder", function()
  local saved_lovr = rawget(_G, "lovr")
  local written
  _G.lovr = { filesystem = {
    createDirectory = function() return true end,
    write = function(path, content) written = path; return true end,
    getSaveDirectory = function() return "/save" end,
  } }
  local notebook = Notebook.new({ name = "nested.luanb" })
  local path = Format.save_in(notebook, "notebooks/work")
  eq(path, "notebooks/work/nested.luanb")
  eq(written, path)
  eq(notebook._path, path)
  _G.lovr = saved_lovr
end)

current = "replace"
test("replace_all replaces literal text across cells", function()
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "foo = 1\nprint(foo)" },
    { kind = "markdown", source = "foo bar" },
  } })
  local count, changed = notebook:replace_all("foo", "baz")
  eq(count, 3); eq(changed, true)
  assert(notebook.cells[1].source:find("baz", 1, true))
  assert(notebook.cells[2].source:find("baz", 1, true))
  eq(select(1, notebook:replace_all("missing", "x")), 0)
  eq(select(1, notebook:replace_all("", "x")), 0)
end)

current = "search"
test("finds literal text case-insensitively and on word boundaries", function()
  local Search = require("notebook.search")
  local text = "Foo foo food foo_bar"
  eq(#Search.matches(text, "foo"), 4)
  eq(#Search.matches(text, "foo", { case_sensitive = true }), 3)
  eq(#Search.matches(text, "foo", { whole_word = true }), 2)
  eq(#Search.matches(text, "foo", { case_sensitive = true,
    whole_word = true }), 1)
  eq(#Search.matches(text, ""), 0)
  eq(Search.count_text(text, "FOO"), 4)
end)
test("collects source and output rows while counting every occurrence", function()
  local Search = require("notebook.search")
  local cells = {
    { source = "foo = 1\nprint(foo)", output = "foo output\nno match" },
    { source = "FOO", output = "" },
  }
  local rows, total = Search.collect(cells, "foo", { limit = 2 })
  eq(total, 4)
  eq(#rows, 2)
  eq(rows[1].cell, 1)
  eq(rows[1].count, 1)
  eq(rows[1].cursor, 1)
  local output_rows = Search.collect(cells, "output", { limit = 10 })
  assert(output_rows[1].line:find("out: ", 1, true) == 1)
end)
test("filters search rows by cell kind", function()
  local Search = require("notebook.search")
  local cells = {
    { kind = "code", source = "needle code", output = "" },
    { kind = "markdown", source = "needle prose", output = "" },
    { kind = "code", source = "other", output = "needle output" },
  }
  local code, code_total = Search.collect(cells, "needle", { kind = "code" })
  eq(code_total, 2)
  eq(#code, 2)
  eq(code[1].cell, 1)
  eq(code[2].cell, 3)
  local prose = Search.collect(cells, "needle", { kind = "markdown" })
  eq(#prose, 1)
  eq(prose[1].cell, 2)
  eq(#Search.collect(cells, "needle", { kind = "none" }), 0)
end)
test("scopes collection and replacement to one cell", function()
  local Search = require("notebook.search")
  local cells = {
    { source = "needle one", output = "needle out" },
    { source = "needle two", output = "" },
  }
  local rows, total = Search.collect(cells, "needle", { cell = 2 })
  eq(total, 1)
  eq(#rows, 1)
  eq(rows[1].cell, 2)
  eq(rows[1].line, "needle two")
  local count, changed = Search.replace_cells(cells, "needle", "thread",
    { cell = 2 })
  eq(count, 1)
  eq(changed, true)
  eq(cells[1].source, "needle one")
  eq(cells[2].source, "thread two")
  local none = Search.collect(cells, "needle", { cell = 99 })
  eq(#none, 0)
end)
test("collects matches across every open notebook", function()
  local Search = require("notebook.search")
  local notebooks = {
    Notebook.new({ name = "one.luanb", cells = {
      { kind = "markdown", source = "# One\nneedle here" },
      { kind = "code", source = "print('needle')", output = "needle out" },
    } }),
    Notebook.new({ name = "two.luanb", cells = {
      { kind = "code", source = "local Needle = 2\nreturn Needle" },
    } }),
  }
  local rows, total = Search.collect_notebooks(notebooks, "needle")
  eq(total, 5)
  eq(#rows, 5)
  eq(rows[1].notebook, 1)
  eq(rows[1].title, "One")
  eq(rows[1].cell, 1)
  eq(rows[1].cursor, 7)
  eq(rows[4].notebook, 2)
  eq(rows[4].cell, 1)
  local _, exact = Search.collect_notebooks(notebooks, "Needle",
    { case_sensitive = true })
  eq(exact, 2)
  local _, bounded = Search.collect_notebooks(notebooks, "needle",
    { whole_word = true })
  eq(bounded, 5)
  local limited, all = Search.collect_notebooks(notebooks, "needle",
    { limit = 2 })
  eq(all, 5)
  eq(#limited, 2)
  local none = Search.collect_notebooks(notebooks, "")
  eq(#none, 0)
end)
test("replaces with case and whole-word options and clamps cursors", function()
  local Search = require("notebook.search")
  local replaced, count = Search.replace_text("Foo foo food foo_bar", "foo",
    "x", { whole_word = true })
  eq(count, 2)
  eq(replaced, "x x food foo_bar")
  local exact, exact_count = Search.replace_text("Foo foo", "foo", "x",
    { case_sensitive = true })
  eq(exact_count, 1)
  eq(exact, "Foo x")
  local cells = { { source = "foo foo", cursor = 7 } }
  local total, changed = Search.replace_cells(cells, "foo", "baz")
  eq(total, 2); eq(changed, true)
  eq(cells[1].source, "baz baz")
  eq(cells[1].cursor, 7)
end)
test("replace_all honours case-sensitive and whole-word options", function()
  local notebook = Notebook.new({ cells = {
    { kind = "code", source = "foo Foo food foo_bar" },
  } })
  local count = notebook:replace_all("foo", "x",
    { case_sensitive = true, whole_word = true })
  eq(count, 1)
  eq(notebook.cells[1].source, "x Foo food foo_bar")
  local all = notebook:replace_all("foo", "x", { whole_word = true })
  eq(all, 1)
  eq(notebook.cells[1].source, "x x food foo_bar")
end)

current = "search regex"
test("matches Lua patterns and reports malformed patterns", function()
  local Search = require("notebook.search")
  local text = "alpha beta 42\nalpha gamma 7"
  local matches = Search.matches(text, "(%a+)%s+(%a+)%s+(%d+)",
    { regex = true })
  eq(#matches, 2)
  eq(matches[1][1], 1)
  local ok, err = Search.validate("(", { regex = true })
  eq(ok, false)
  assert(err ~= nil)
  local rows, total, pattern_error = Search.collect({ { source = "x" } }, "(",
    { regex = true })
  eq(#rows, 0)
  eq(total, 0)
  assert(pattern_error ~= nil)
  eq(#Search.matches("Alpha alpha", "alpha", { regex = true }), 2)
  eq(#Search.matches("foo food", "foo", { regex = true,
    whole_word = true }), 1)
  eq(#Search.matches("abc", "%a*", { regex = true }), 1)
end)
test("expands numbered captures in regex replacements", function()
  local Search = require("notebook.search")
  local text = "alpha beta 42\nalpha gamma 7"
  local replaced, count = Search.replace_text(text,
    "(%a+)%s+(%a+)%s+(%d+)", "%3:%1", { regex = true })
  eq(count, 2)
  eq(replaced, "42:alpha\n7:alpha")
  local wrapped = Search.replace_text("a1", "%d", "[%0]", { regex = true })
  eq(wrapped, "a[1]")
  local literal_percent = Search.replace_text("a1", "%d", "[%%]",
    { regex = true })
  eq(literal_percent, "a[%]")
  local whole, whole_count = Search.replace_text("foo food", "foo", "x",
    { regex = true, whole_word = true })
  eq(whole_count, 1)
  eq(whole, "x food")
  local cells = { { source = "a1 b2", cursor = 6 } }
  local total, changed = Search.replace_cells(cells, "(%a)(%d)", "%2%1",
    { regex = true })
  eq(total, 2)
  eq(changed, true)
  eq(cells[1].source, "1a 2b")
  eq(cells[1].cursor, 6)
end)

current = "recent"
test("recent files round-trip and cap", function()
  local text = Format.encode_recent({ "/a.luanb", "/b.luanb" })
  local paths = Format.decode_recent(text)
  eq(#paths, 2); eq(paths[2], "/b.luanb")
  eq(#Format.decode_recent("bad"), 0)
end)

current = "html"
test("html export has structure, output classes, and backlinks", function()
  local a = Notebook.new({ name = "a.luanb", cells = {
    { kind = "markdown", source = "# Hello\n\n[[b]]" },
    { kind = "code", source = "print(1)" },
  } })
  a.cells[2].output = "1"
  local b = Notebook.new({ name = "b.luanb", cells = {
    { kind = "markdown", source = "[[" .. a:title() .. "]]" },
  } })
  local html = Format.to_html(a, Format.backlinks({ a, b }, a:title()))
  assert(html:find('class="cell"', 1, true))
  assert(html:find('class="output"', 1, true))
  assert(html:find("Backlinks:", 1, true))
  eq(#Format.wiki_links(a.cells), 1)
end)

io.write(string.format("\n\n%d tests, %d passed, %d failed\n", passed + failed,
  passed, failed))
if failed > 0 then
  for _, failure in ipairs(failures) do io.write("\n" .. failure .. "\n") end
  os.exit(1)
end
