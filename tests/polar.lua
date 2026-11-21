-- Pure-Lua coverage for shared polar geometry and the live LÖVR renderer.
-- The fake pass records draw calls, so this runs on LuaJIT and PUC Lua 5.1
-- without a display.
local script = arg and arg[0] or "tests/polar.lua"
local root = script:match("^(.*)[/\\]tests[/\\][^/\\]+$") or "."
if root == "" then root = "." end
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Polar = require("notebook.polar")
local Format = require("notebook.format")
local Theme = require("ui.theme")
local Plot = require("ui.plot")
local json = require("notebook.json")

local passed, failed = 0, 0
local failures = {}

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write(".")
  else
    failed = failed + 1
    failures[#failures + 1] = string.format("[polar] %s\n  %s", name,
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

local function near(actual, expected, tolerance, label)
  if math.abs(actual - expected) > (tolerance or 1e-6) then
    error(string.format("%s: expected %.6f, got %.6f", label or "value",
      expected, actual), 2)
  end
end

local function contains(value, needle, label)
  if value:find(needle, 1, true) == nil then
    error(string.format("%s: missing %q", label or "value", needle), 2)
  end
end

local function count_plain(value, needle)
  local count, position = 0, 1
  while true do
    local found = value:find(needle, position, true)
    if found == nil then return count end
    count = count + 1
    position = found + #needle
  end
end

local function new_pass()
  local calls = {}
  local pass = setmetatable({}, {
    __index = function(self, name)
      local function record(_, ...)
        calls[#calls + 1] = { name = name, args = { ... } }
      end
      rawset(self, name, record)
      return record
    end,
  })
  return pass, calls
end

local function named(calls, name)
  local result = {}
  for _, call in ipairs(calls) do
    if call.name == name then result[#result + 1] = call end
  end
  return result
end

local function text_values(calls)
  local values = {}
  for _, call in ipairs(named(calls, "text")) do
    values[#values + 1] = call.args[1]
  end
  return values
end

local function sample_scene()
  return {
    type = "luaplotlib", orientation = "polar", title = "rose <r>",
    polar = {
      theta_zero = 0,
      theta_direction = "counterclockwise",
      rmax = 2,
      theta_ticks = {
        { value = 0, label = "0" },
        { value = math.pi / 2, label = "90" },
      },
      r_ticks = {
        { value = 1, label = "1" },
        { value = 2, label = "2" },
      },
      series = {
        { kind = "line", theta = { 0, math.pi / 2 }, r = { 1, 2 },
          style = { color = "#1f77b4", label = "rose" } },
        { kind = "scatter", theta = { 0 }, r = { 1 },
          style = { color = "#ff7f0e", radius = 4, label = "samples" } },
        { kind = "bar", theta = { math.pi }, r = { 1.5 },
          widths = { 0.4 }, colors = { "#2ca02c" } },
      },
    },
  }
end

test("resolves config, palette, and observed rmax", function()
  local scene = sample_scene()
  local resolved = Polar.resolve(scene)
  eq(resolved.rmax, 2)
  eq(resolved.theta_zero, 0)
  eq(resolved.direction, 1)
  eq(#resolved.series, 3)
  eq(resolved.series[1].kind, "line")
  eq(resolved.series[1].color, "#1f77b4")
  eq(resolved.series[2].points[1].radius, 4)
  eq(resolved.series[3].bars[1].color, "#2ca02c")

  local fallback = {
    type = "luaplotlib", orientation = "polar",
    polar = { series = {
      { kind = "line", theta = { 0 }, r = { -3 } },
      { kind = "line", theta = { 0 }, r = { 2 } },
    } },
  }
  local auto = Polar.resolve(fallback)
  eq(auto.rmax, 3)
  eq(auto.series[1].color, Polar.PALETTE[1])
  eq(auto.series[2].color, Polar.PALETTE[2])
end)

test("projects screen coordinates and clamps out-of-range radii", function()
  local x, y, angle = Polar.project(100, 100, 40, 2, 0, 1, 0, 1)
  near(x, 120); near(y, 100); near(angle, 0)
  x, y = Polar.project(100, 100, 40, 2, 0, 1, math.pi / 2, 1)
  near(x, 100); near(y, 80)
  x, y = Polar.project(100, 100, 40, 2, 0, 1, 0, 99)
  near(x, 140); near(y, 100)
  x, y = Polar.project(100, 100, 40, 2, 0, -1, math.pi / 2, 1)
  near(x, 100); near(y, 120)
end)

test("filters ticks and omits long labels", function()
  local polar = {
    r_ticks = {
      { value = 0, label = "zero" },
      { value = 1, label = "1" },
      { value = 3, label = "3" },
      { value = 2, label = string.rep("x", 13) },
    },
    theta_ticks = {
      { value = 0, label = string.rep("y", 19) },
      { value = math.pi, label = "180" },
    },
  }
  local rings = Polar.rings(polar, 2)
  eq(#rings, 2)
  eq(Polar.radius_label(rings[1]), "1")
  eq(Polar.radius_label(rings[2]), nil)
  local spokes = Polar.spokes(polar)
  eq(#spokes, 2)
  eq(Polar.theta_label(spokes[1]), nil)
  eq(Polar.theta_label(spokes[2]), "180")
  local fallback_rings = Polar.rings({}, 2)
  eq(#fallback_rings, 4)
  eq(Polar.radius_label(fallback_rings[1]), "0.5")
  local fallback_spokes = Polar.spokes({})
  eq(#fallback_spokes, 12)
  eq(Polar.theta_label(fallback_spokes[2]), "30°")
end)

test("splits wide bars, rotates negative radii, and clamps", function()
  local full = Polar.bar_sectors({ theta = 0, r = 1, width = 7 }, 100, 2, 0, 1)
  eq(#full, 1)
  eq(full[1].full, true)
  near(full[1].radius, 50)
  local wide = Polar.bar_sectors({ theta = 0, r = 1, width = 3.5 }, 100, 2, 0, 1)
  eq(#wide, 2)
  near(wide[1].start_angle, -1.75)
  near(wide[2].end_angle, 1.75)
  local negative = Polar.bar_sectors({ theta = 0, r = -1, width = 0.2 },
    100, 2, 0, 1)
  eq(#negative, 1)
  near(negative[1].start_angle, math.pi - 0.1)
  local clamped = Polar.bar_sectors({ theta = 0, r = 100, width = 0.2 },
    100, 2, 0, 1)
  near(clamped[1].radius, 100)
  local points = Polar.sector_points(10, 20, clamped[1])
  eq(#points % 3, 0)
  eq(points[1], 10); eq(points[2], 20); eq(points[3], 0)
  for index = 4, #points, 3 do
    local dx = points[index] - 10
    local dy = points[index + 1] - 20
    assert(math.sqrt(dx * dx + dy * dy) <= 100.001)
  end
end)

test("draws polar frame, rings, spokes, labels, and series", function()
  local pass, calls = new_pass()
  Plot.draw(pass, {}, sample_scene(), 0, 0, 800, 300)
  local cx, cy, radius = Plot.polar_layout(0, 0, 800, 300)
  near(cx, 400); near(cy, 152); near(radius, 108)

  local circles = named(calls, "circle")
  eq(#circles, 4) -- two rings, the frame, and one scatter point
  local ring_54, ring_108, frame = false, false, false
  for _, call in ipairs(circles) do
    if call.args[4] == 54 then ring_54 = true end
    if call.args[4] == 108 and call.args[9] == "line" then
      ring_108 = true
    end
    if call.args[4] == 108 and call.args[9] == "line" then frame = true end
  end
  assert(ring_54 and ring_108 and frame, "expected ring/frame circles")

  local lines = named(calls, "line")
  eq(#lines, 3) -- two theta spokes and one line segment
  local series_line
  for _, call in ipairs(lines) do
    if call.args[1] == 454 and call.args[2] == 152 then series_line = call end
  end
  assert(series_line, "missing projected line start")
  near(series_line.args[4], 400)
  near(series_line.args[5], 44)

  local polygons = named(calls, "polygon")
  eq(#polygons, 1)
  local points = polygons[1].args[1]
  eq(points[1], 400); eq(points[2], 152); eq(points[3], 0)
  assert(#points >= 9)

  local values = text_values(calls)
  local seen = {}
  for _, value in ipairs(values) do seen[value] = true end
  assert(seen["rose <r>"] and seen["0"] and seen["90"])
  assert(seen["1"] and seen["2"])
end)

test("draws clockwise theta and auto-rmax on the frame", function()
  local scene = {
    type = "luaplotlib", orientation = "polar",
    polar = {
      theta_direction = "clockwise",
      theta_ticks = { { value = 0, label = "0" } },
      series = {
        { kind = "line", theta = { 0, math.pi / 2 }, r = { 1, 1 } },
      },
    },
  }
  local pass, calls = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 800, 300)
  local _, cy, radius = Plot.polar_layout(0, 0, 800, 300)
  local lines = named(calls, "line")
  local projected
  for _, call in ipairs(lines) do
    if call.args[5] == cy + radius then projected = call end
  end
  assert(projected, "missing clockwise segment")
  near(projected.args[4], 400)
  eq(Polar.resolve(scene).rmax, 1)
end)

test("clamps oversized data and tolerates non-finite points", function()
  local pass, calls = new_pass()
  local scene = {
    type = "luaplotlib", orientation = "polar",
    polar = {
      rmax = 2,
      theta_ticks = { { value = 0, label = "0" } },
      series = {
        { kind = "line", theta = { 0, 1 / 0, 2 }, r = { 1, 2, 0 / 0 } },
        { kind = "line", theta = { 0, 0 }, r = { 0, 99 } },
      },
    },
  }
  Plot.draw(pass, {}, scene, 0, 0, 800, 300)
  local cx, cy, radius = Plot.polar_layout(0, 0, 800, 300)
  local lines = named(calls, "line")
  local clamped
  for _, call in ipairs(lines) do
    if call.args[4] == cx + radius and call.args[5] == cy then
      clamped = call
    end
  end
  assert(clamped, "oversized radius did not clamp to the frame")
  eq(#named(calls, "polygon"), 0)
end)

test("draws fallback rings and spokes for an empty scene", function()
  local pass, calls = new_pass()
  Plot.draw(pass, {}, { type = "luaplotlib", orientation = "polar",
    polar = {} }, 0, 0, 800, 300)
  eq(#named(calls, "circle"), 5) -- four fallback rings plus the frame
  eq(#named(calls, "line"), 12)
  eq(#named(calls, "polygon"), 0)
  local values = text_values(calls)
  assert(#values >= 16) -- four radius labels and twelve degree labels
end)

test("long polar labels are omitted by both renderers", function()
  local long_radius = string.rep("r", 40)
  local long_theta = string.rep("t", 40)
  local scene = {
    type = "luaplotlib", orientation = "polar",
    polar = {
      rmax = 1,
      r_ticks = { { value = 0.5, label = long_radius } },
      theta_ticks = { { value = 0, label = long_theta } },
    },
  }
  local text = Format.scene_svg(scene, 480, 240)
  assert(text:find(long_radius, 1, true) == nil)
  assert(text:find(long_theta, 1, true) == nil)
  local pass, calls = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 800, 300)
  for _, value in ipairs(text_values(calls)) do
    assert(value ~= long_radius and value ~= long_theta)
  end
end)

test("export and live agree on rmax, projection, and bar sectors", function()
  local scene = sample_scene()
  local resolved = Polar.resolve(scene)
  local svg = Format.scene_svg(scene, 480, 240)
  contains(svg, 'data-rmax="2.00"', "rmax")
  contains(svg, 'data-theta-zero="0.00"', "theta zero")
  contains(svg, 'data-theta-direction="counterclockwise"', "direction")

  local left, top = 54, 22
  local right, bottom = 480 - 20, 240 - 30
  local plot_w, plot_h = right - left, bottom - top
  local radius = Polar.frame_radius(plot_w, plot_h)
  local cx, cy = left + plot_w / 2, top + plot_h / 2
  local projected = svg:match('scene%-polar%-line" points="([^"]+)"')
  assert(projected, "missing exported polar line")
  local first_x, first_y = projected:match("([%d%.%-]+),([%d%.%-]+)")
  local expected_x, expected_y = Polar.project(cx, cy, radius, resolved.rmax,
    resolved.theta_zero, resolved.direction, 0, 1)
  near(tonumber(first_x), expected_x, 0.01)
  near(tonumber(first_y), expected_y, 0.01)

  local export_bars = count_plain(svg, 'class="scene-polar-bar"')
  local live_bars = 0
  for _, series in ipairs(resolved.series) do
    if series.bars ~= nil then
      for _, bar in ipairs(series.bars) do
        live_bars = live_bars + #Polar.bar_sectors(bar, radius, resolved.rmax,
          resolved.theta_zero, resolved.direction)
      end
    end
  end
  eq(export_bars, live_bars)
  local pass, calls = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 800, 300)
  eq(#named(calls, "polygon"), live_bars)
end)

test("fallback rmax matches between export and live", function()
  local scene = {
    type = "luaplotlib", orientation = "polar",
    polar = {
      theta_direction = "clockwise",
      series = {
        { kind = "line", theta = { 0, math.pi }, r = { 1, -2.5 } },
      },
    },
  }
  local resolved = Polar.resolve(scene)
  eq(resolved.rmax, 2.5)
  contains(Format.scene_svg(scene, 480, 240), 'data-rmax="2.50"', "auto rmax")
  local pass, calls = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 800, 300)
  local cx, cy, radius = Plot.polar_layout(0, 0, 800, 300)
  local lines = named(calls, "line")
  local endpoint
  for _, call in ipairs(lines) do
    if call.args[1] ~= cx or call.args[2] ~= cy then endpoint = call end
  end
  assert(endpoint, "missing auto-rmax segment")
  -- A negative radius flips the point through the center.
  local angle = resolved.theta_zero + math.pi
  local ratio = -1
  near(endpoint.args[4], cx + radius * ratio * math.cos(angle))
  near(endpoint.args[5], cy - radius * ratio * math.sin(angle))
end)

test("samples long polar series with the documented caps", function()
  eq(Polar.sample_step(0), 1)
  eq(Polar.sample_step(96, Polar.LINE_SAMPLE_LIMIT), 1)
  eq(Polar.sample_step(1600, Polar.LINE_SAMPLE_LIMIT), 2)
  eq(Polar.sample_step(401, Polar.SCATTER_SAMPLE_LIMIT), 2)
  local theta, r = {}, {}
  for index = 1, 1000 do
    theta[index] = index * 0.001
    r[index] = 1
  end
  local pass, calls = new_pass()
  Plot.draw(pass, {}, {
    type = "luaplotlib", orientation = "polar",
    polar = {
      rmax = 1,
      theta_ticks = { { value = 0, label = "0" } },
      series = { { kind = "line", theta = theta, r = r } },
    },
  }, 0, 0, 800, 300)
  eq(#named(calls, "line"), 1 + 499)
end)

test("cartesian scenes keep the original draw path", function()
  Theme.set("dark")
  local pass, calls = new_pass()
  local scene = {
    type = "luaplotlib", title = "sin", xlim = { 0, 1 }, ylim = { -1, 1 },
    grid = true,
    series = {
      { kind = "line", x = { 0, 0.5, 1 }, y = { 0, 1, 0 },
        style = { color = "#1f77b4" } },
      { kind = "scatter", x = { 0.5 }, y = { 1 },
        style = { color = "#ff7f0e", radius = 4 } },
    },
  }
  Plot.draw(pass, {}, scene, 0, 0, 800, 300)
  eq(#named(calls, "plane"), 2) -- scene background and plot region
  eq(#named(calls, "polygon"), 0)
  eq(#named(calls, "circle"), 1) -- only the scatter point
  local values = text_values(calls)
  local seen = {}
  for _, value in ipairs(values) do seen[value] = true end
  assert(seen["sin"])
end)

-- webapp/tests/polar.test.mjs reads this same fixture and asserts the same
-- numbers with the browser module.  A drift on either side breaks one suite.
test("matches the cross-renderer browser fixture", function()
  local path = root .. "/webapp/tests/fixtures/polar-parity.json"
  local handle = assert(io.open(path, "rb"))
  local text = handle:read("*a")
  handle:close()
  local fixture = assert(json.decode(text))
  local expected = fixture.expected
  local resolved = Polar.resolve(fixture.scene)

  eq(resolved.rmax, expected.rmax)
  eq(resolved.observed, expected.observed)
  eq(resolved.direction, expected.direction)
  for index, kind in ipairs(expected.series_kinds) do
    eq(resolved.series[index].kind, kind)
  end

  local layout = fixture.layout
  local cx, cy, radius = Plot.polar_layout(0, 0, layout.width, layout.height)
  near(cx, layout.cx)
  near(cy, layout.cy)
  near(radius, layout.radius)
  near(Polar.frame_radius(layout.width - 104, layout.height - 64),
    layout.radius)

  for _, projection in ipairs(expected.projection) do
    local x, y, angle = Polar.project(cx, cy, radius, resolved.rmax,
      resolved.theta_zero, resolved.direction, projection.theta,
      projection.r)
    near(x, projection.x)
    near(y, projection.y)
    near(angle, projection.angle)
  end

  local rings = Polar.rings(resolved.polar, resolved.rmax)
  for index, tick in ipairs(rings) do
    eq(Polar.radius_label(tick), expected.radius_labels[index])
  end
  local spokes = Polar.spokes(resolved.polar)
  for index, tick in ipairs(spokes) do
    eq(Polar.theta_label(tick), expected.theta_labels[index])
  end

  local sectors = Polar.bar_sectors(resolved.series[2].bars[1], radius,
    resolved.rmax, resolved.theta_zero, resolved.direction)
  eq(#sectors, 1)
  near(sectors[1].radius, expected.bar_sector.radius)
  near(sectors[1].start_angle, expected.bar_sector.start_angle)
  near(sectors[1].end_angle, expected.bar_sector.end_angle)
end)

print(string.format("\npolar tests: %d passed, %d failed", passed, failed))
if failed > 0 then
  io.stderr:write(table.concat(failures, "\n") .. "\n")
  os.exit(1)
end
