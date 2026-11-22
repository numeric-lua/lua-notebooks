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
  eq(#notebooks[1].cells, 19)
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
    { kind = "markdown", source = "# Heading" },
    { kind = "code", source = "print('<tag>')" },
  } })
  local text = Format.to_html(notebook)
  assert(text:find("<!doctype html>", 1, true))
  assert(text:find("&lt;tag&gt;", 1, true))
  assert(text:find('<h1 id="heading">Heading</h1>', 1, true))
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
