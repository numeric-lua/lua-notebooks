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

local function read_polar_fixture()
  local path = root .. "/webapp/tests/fixtures/polar-parity.json"
  local handle = assert(io.open(path, "rb"))
  local text = handle:read("*a")
  handle:close()
  return assert(json.decode(text))
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

local function large_field_scene(rows, cols)
  rows = rows or 65
  cols = cols or 65
  local values = {}
  for row = 1, rows do
    values[row] = {}
    for col = 1, cols do
      values[row][col] = (row - 1) / (rows - 1)
    end
  end
  return {
    type = "luaplotlib", orientation = "polar",
    title = "large polar field",
    polar = {
      rmax = 2,
      theta_ticks = { { value = 0, label = "0" } },
      r_ticks = { { value = 1, label = "1" }, { value = 2, label = "2" } },
      heatmaps = { {
        rows = rows, cols = cols, values = values,
        vmin = 0, vmax = 1, rmin = 0, rmax = 2,
        theta_min = 0, theta_max = 2 * math.pi,
        alpha = 1, label = "large", colorbar = true,
      } },
      colorbar = { vmin = 0, vmax = 1, ticks = { 0, 0.5, 1 },
        label = "density" },
    },
  }
end

local function quiver_scene(options)
  options = options or {}
  return {
    type = "luaplotlib", orientation = "polar", title = "quiver",
    polar = {
      theta_zero = options.theta_zero or 0,
      theta_direction = options.theta_direction or "counterclockwise",
      rmax = 6,
      theta_ticks = { { value = 0, label = "0" } },
      r_ticks = { { value = 3, label = "3" } },
      series = { {
        kind = "quiver",
        theta = options.theta or { 0, math.pi / 2, 0, 0 },
        r = options.r or { 3, 3, 3, 3 },
        u = options.u or { 1, 1, 0, 0 },
        v = options.v or { 0, 0, 1, 1 },
        scale = options.scale == nil and 20 or options.scale,
        pivot = options.pivot or "tail",
        max_arrows = options.max_arrows,
        normalize = options.normalize,
        style = {
          color = "#1f77b4", linewidth = 1.2, head = 5,
          alpha = options.alpha or 1,
        },
      } },
    },
  }
end

local function stream_scene(options)
  options = options or {}
  return {
    type = "luaplotlib", orientation = "polar", title = "streamplot",
    polar = {
      theta_zero = options.theta_zero or 0,
      theta_direction = options.theta_direction or "counterclockwise",
      rmax = options.rmax or 2,
      theta_ticks = { { value = 0, label = "0" } },
      r_ticks = { { value = 1, label = "1" }, { value = 2, label = "2" } },
      series = { {
        kind = "streamplot",
        theta = options.theta or
          { 0, math.pi / 2, math.pi, 3 * math.pi / 2, 2 * math.pi },
        r = options.r or { 0.5, 1, 1.5, 2 },
        lines = options.lines or {
          { theta = { 0, 0.5, 1 }, r = { 1, 1.2, 1.4 },
            arrows = { { theta = 0.5, r = 1.2, angle = -30 } } },
          { theta = { 2, 2.5, 3, 3.5 }, r = { 0.8, 0.9, 1, 1.1 },
            arrows = { { theta = 3, r = 1, angle = 120 } } },
        },
        periodic = options.periodic,
        density = options.density,
        step = options.step,
        resolved_step = options.resolved_step,
        step_mode = options.step_mode,
        max_steps = options.max_steps,
        max_lines = options.max_lines,
        max_points = options.max_points,
        arrows = options.arrows,
        head = options.head,
        truncated = options.truncated,
        style = {
          color = options.color or "#2ca02c",
          linewidth = options.linewidth == nil and 1.5 or options.linewidth,
          head = options.style_head or 6,
          alpha = options.alpha or 0.9,
          label = "flow",
        },
      } },
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


test("maps field values through the shared viridis palette", function()
  eq(Polar.heat_color(0, 0, 5), "#440154")
  eq(Polar.heat_color(5, 0, 5), "#fde725")
  eq(Polar.heat_color(1, 0, 5), "#345382")
  eq(Polar.heat_color(-1, 0, 5), "#440154")
  eq(Polar.heat_color(9, 0, 5), "#fde725")
  eq(Polar.heat_color(0, 0, 0), "#440154")
  eq(Polar.compact_number(0), "0")
  eq(Polar.compact_number(2.5), "2.5")
  eq(Polar.compact_number(1234), "1230")
  eq(Polar.compact_number(0.0001), "0.0001")
  eq(Polar.compact_number(0.00001), "1e-5")
  eq(Polar.compact_number(1 / 0), nil)

  local heatmaps = Polar.collect_heatmaps({
    heatmaps = {
      { rows = 2, cols = 2, values = { { 1, 2 }, { 3, 4 } } },
      { rows = "bad", cols = 2, values = {} },
    },
  })
  eq(#heatmaps, 1)
  eq(heatmaps[1].vmin, 1)
  eq(heatmaps[1].vmax, 4)
  eq(heatmaps[1].rmin, 0)
  eq(heatmaps[1].rmax, 2)
  eq(heatmaps[1].theta_max, 2 * math.pi)
  eq(heatmaps[1].alpha, 1)
  local contours = Polar.collect_contours({
    contours = {
      { levels = { { level = 2, segments = { { 0, 1, 1, 2 }, { 1 } } } },
        labels = true, style = { color = "#112233" } },
      { levels = {} },
    },
  })
  eq(#contours, 1)
  eq(#contours[1].levels[1].segments, 1)
  eq(contours[1].style.color, "#112233")
  eq(contours[1].style.linestyle, "solid")
end)

test("derives and tolerates malformed field metadata", function()
  local derived = Polar.resolve({
    type = "luaplotlib", orientation = "polar",
    polar = {
      heatmaps = { {
        rows = 1, cols = 1, values = { { 0.5 } },
        vmin = 0, vmax = 1, colorbar = true,
      } },
    },
  })
  assert(derived.colorbar ~= nil, "heatmap colorbar flag was ignored")
  eq(#derived.colorbar.ticks, 3)
  eq(Polar.colorbar_ticks(derived.colorbar)[2].label, "0.5")

  local scene = {
    type = "luaplotlib", orientation = "polar",
    polar = {
      rmax = 2,
      heatmaps = { {
        rows = 2, cols = 2,
        values = { { 1 / 0, 2 }, { 3, 0 / 0 } },
        vmin = 0, vmax = 0, alpha = 2,
      } },
      contours = { {
        levels = { { level = 1, segments = {
          { 0, 0, 0 / 0, 1 }, { 1, 2, 3, 4 },
        } } },
        labels = true,
      } },
      colorbar = { vmin = 0, vmax = 0 },
    },
  }
  local resolved = Polar.resolve(scene)
  eq(#resolved.heatmaps, 1)
  eq(resolved.heatmaps[1].vmax, 1)
  eq(resolved.heatmaps[1].alpha, 1)
  eq(resolved.colorbar, nil)
  eq(#resolved.contours[1].levels[1].segments, 1)
  local cells = Polar.heatmap_cells(resolved.heatmaps[1], 100, 100, 50,
    resolved.rmax, 0, 1)
  eq(#cells, 4)
  for _, cell in ipairs(cells) do
    assert(cell.color:match("^#%x%x%x%x%x%x$") ~= nil)
  end
  local svg = Format.scene_svg(scene, 480, 240)
  assert(svg:find("nan", 1, true) == nil)
  assert(svg:find("inf", 1, true) == nil)
  local pass = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 480, 240)
end)

test("projects heatmap cells, contour edges, and the colorbar", function()
  local heatmap = {
    rows = 2, cols = 3, values = { { 0, 1, 2 }, { 3, 4, 5 } },
    vmin = 0, vmax = 5, rmin = 0.5, rmax = 2,
    theta_min = 0, theta_max = math.pi, alpha = 0.9,
  }
  local cx, cy, radius = Polar.frame_layout(52, 34, 548, 200, true)
  near(cx, 272); near(cy, 117); near(radius, 73)
  local cells = Polar.heatmap_cells(heatmap, cx, cy, radius, 2, 0, 1)
  eq(#cells, 6)
  eq(cells[1].row, 1); eq(cells[1].col, 1)
  eq(cells[1].color, "#440154")
  eq(cells[6].color, "#fde725")
  near(cells[1].inner_radius, 18.25)
  near(cells[1].outer_radius, 45.625)
  near(cells[1].start_angle, 0)
  near(cells[1].end_angle, math.pi / 3)
  near(cells[5].inner_radius, 45.625)
  near(cells[5].outer_radius, 73)

  local full = {
    rows = 1, cols = 1, values = { { 1 } },
    vmin = 0, vmax = 1, rmin = 0.5, rmax = 1,
    theta_min = 0, theta_max = 2 * math.pi, alpha = 1,
  }
  local ring = Polar.heatmap_cells(full, 100, 100, 50, 1, 0, 1)
  eq(#ring, 1)
  eq(#ring[1].parts, Polar.FULL_TURN_PARTS)
  local disc = Polar.heatmap_cells({
    rows = 1, cols = 1, values = { { 1 } }, vmin = 0, vmax = 1,
    rmin = 0, rmax = 1, theta_min = 0, theta_max = 2 * math.pi,
  }, 100, 100, 50, 1, 0, 1)
  eq(disc[1].full_disc, true)

  local contour = { rmin = 0, rmax = 2 }
  local segment = { 0, 0.5, math.pi / 2, 1.5 }
  local points = Polar.contour_segment_points(contour, segment, cx, cy, radius,
    2, 0, 1)
  eq(#points, 25)
  near(points[1][1], 290.25)
  near(points[1][2], 117)
  near(points[#points][1], 272)
  near(points[#points][2], 62.25)

  local bar = { vmin = 0, vmax = 5, ticks = { 0, 2.5, 5 } }
  local bx, by, bw, bh = Polar.colorbar_layout(cx, cy, radius)
  near(bx, 361); near(by, 54.95); near(bw, 16); near(bh, 124.1)
  local ticks = Polar.colorbar_ticks(bar)
  eq(#ticks, 3)
  eq(ticks[1].label, "0"); eq(ticks[2].label, "2.5")
  eq(ticks[3].fraction, 1)
  local steps = Polar.colorbar_steps(bar)
  eq(#steps, Polar.COLORBAR_STEPS)
  eq(steps[1].y0, 0)
  eq(steps[#steps].y1, 1)
end)

test("draws polar fields and a colorbar in the live viewport", function()
  local fixture = read_polar_fixture()
  local pass, calls = new_pass()
  Plot.draw(pass, {}, fixture.field_scene, 0, 0, 600, 230)
  local cx, cy, radius = Plot.polar_layout(0, 0, 600, 230, true)
  near(cx, 272); near(cy, 117); near(radius, 73)

  eq(#named(calls, "polygon"), 6) -- six annular heatmap cells
  eq(#named(calls, "plane"), 1 + Polar.COLORBAR_STEPS)
  local circles = named(calls, "circle")
  eq(#circles, 5) -- four rings and the frame
  local lines = named(calls, "line")
  eq(#lines, 2 + 24 + 24 + 1 + 4 + 3)
  local values = text_values(calls)
  local seen = {}
  for _, value in ipairs(values) do seen[value] = true end
  assert(seen["polar field"] and seen["density"] and seen["2.5"])
  assert(seen["0.5"] and seen["1.5"] and seen["90"])
end)

test("exports polar fields and the colorbar in the SVG preview", function()
  local fixture = read_polar_fixture()
  local svg = Format.scene_svg(fixture.field_scene, 600, 230)
  contains(svg, 'data-has-colorbar="true"', "colorbar flag")
  eq(count_plain(svg, 'class="scene-polar-heatmap-cell"'), 6)
  eq(count_plain(svg, 'class="scene-polar-contour"'), 2)
  eq(count_plain(svg, 'class="scene-polar-colorbar-step"'),
    Polar.COLORBAR_STEPS)
  contains(svg, "scene-polar-contour-label", "contour label")
  contains(svg, "scene-polar-colorbar-title", "colorbar title")
  contains(svg, ">density<", "colorbar label")
  contains(svg, ">2.5<", "contour label")
  assert(svg:find("nan", 1, true) == nil)
  assert(svg:find("inf", 1, true) == nil)
  local summary = Format.scene_summary(fixture.field_scene)
  eq(summary.count, fixture.field_expected.summary.count)
  eq(summary.points, fixture.field_expected.summary.points)
end)

test("matches the cross-renderer polar field fixture", function()
  local fixture = read_polar_fixture()
  local expected = fixture.field_expected
  local scene = fixture.field_scene
  local resolved = Polar.resolve(scene)
  eq(resolved.rmax, expected.rmax)
  eq(resolved.observed, expected.observed)

  local layout = fixture.field_layout
  local cx, cy, radius = Polar.frame_layout(52, 34, layout.width - 52,
    layout.height - 30, layout.has_colorbar)
  near(cx, layout.cx)
  near(cy, layout.cy)
  near(radius, layout.radius)

  local cells = Polar.heatmap_cells(resolved.heatmaps[1], cx, cy, radius,
    resolved.rmax, resolved.theta_zero, resolved.direction)
  eq(#cells, expected.heatmap_cells)
  for index, color in ipairs(expected.heat_colors) do
    eq(cells[index].color, color)
  end
  local first = expected.first_cell
  eq(cells[1].row, first.row)
  eq(cells[1].col, first.col)
  near(cells[1].inner_radius, first.inner_radius)
  near(cells[1].outer_radius, first.outer_radius)
  near(cells[1].start_angle, first.start_angle)
  near(cells[1].end_angle, first.end_angle)

  local contour = resolved.contours[1]
  for index, segment in ipairs(contour.levels[1].segments) do
    local points = Polar.contour_segment_points(contour, segment, cx, cy,
      radius, resolved.rmax, resolved.theta_zero, resolved.direction)
    eq(#points, expected.contour_point_counts[index])
    if index == 1 then
      near(points[1][1], expected.contour_first.x)
      near(points[1][2], expected.contour_first.y)
    else
      near(points[#points][1], expected.contour_second_last.x)
      near(points[#points][2], expected.contour_second_last.y)
    end
  end
  local label = Polar.contour_label(contour, contour.levels[1], cx, cy,
    radius, resolved.rmax, resolved.theta_zero, resolved.direction)
  eq(label.text, expected.contour_label.text)
  near(label.x, expected.contour_label.x, 1e-4)
  near(label.y, expected.contour_label.y, 1e-4)

  local bx, by, bw, bh = Polar.colorbar_layout(cx, cy, radius)
  near(bx, expected.colorbar.x)
  near(by, expected.colorbar.y)
  near(bw, expected.colorbar.width)
  near(bh, expected.colorbar.height)
  local ticks = Polar.colorbar_ticks(resolved.colorbar)
  for index, tick in ipairs(ticks) do
    eq(tick.label, expected.colorbar_labels[index])
  end
end)

test("samples large heatmap fields into covering blocks", function()
  local sampling = Polar.heatmap_sampling(65, 65)
  eq(sampling.sampled, true)
  eq(sampling.row_step, 2)
  eq(sampling.col_step, 1)
  eq(sampling.sampled_rows, 33)
  eq(sampling.sampled_cols, 65)
  eq(sampling.count, 2145)

  local identity = Polar.heatmap_sampling(64, 64)
  eq(identity.sampled, false)
  eq(identity.row_step, 1)
  eq(identity.col_step, 1)
  eq(identity.count, Polar.HEATMAP_CELL_LIMIT)

  for _, shape in ipairs({ { 1, 100000 }, { 100000, 1 }, { 3, 5000 },
      { 128, 33 }, { 1024, 1024 } }) do
    local result = Polar.heatmap_sampling(shape[1], shape[2])
    assert(result.sampled, "expected sampling for a large field")
    assert(result.count <= Polar.HEATMAP_CELL_LIMIT,
      "sampled cell count exceeded the cap")
  end

  local scene = large_field_scene()
  local resolved = Polar.resolve(scene)
  local heatmap = resolved.heatmaps[1]
  eq(heatmap.sampled, true)
  eq(heatmap.row_step, 2)
  eq(heatmap.col_step, 1)
  eq(heatmap.sampled_cells, 2145)
  eq(#heatmap.values, 33)
  eq(#heatmap.values[1], 65)
  eq(heatmap.vmin, 0)
  eq(heatmap.vmax, 1)

  local cells = Polar.heatmap_cells(heatmap, 272, 117, 73, 2, 0, 1)
  eq(#cells, 2145)
  eq(cells[1].row, 1)
  eq(cells[1].col, 1)
  eq(cells[1].row_span, 2)
  eq(cells[1].col_span, 1)
  near(cells[1].inner_radius, 0)
  near(cells[1].outer_radius, 2.2461538461538462)
  eq(cells[1].color, "#440154")
  eq(cells[66].row, 3)
  near(cells[66].inner_radius, cells[1].outer_radius)
  local last = cells[#cells]
  eq(last.row, 65)
  eq(last.col, 65)
  eq(last.row_span, 1)
  near(last.inner_radius, 71.87692307692308)
  near(last.outer_radius, 73)
  near(last.end_angle, 2 * math.pi)
  eq(last.color, "#fde725")

  -- A missing range scans the full matrix before sampling, so normalization
  -- does not depend on which block values were copied.
  local implicit = large_field_scene()
  implicit.polar.heatmaps[1].vmin = nil
  implicit.polar.heatmaps[1].vmax = nil
  implicit.polar.heatmaps[1].values[5][5] = 0 / 0
  local implicit_resolved = Polar.resolve(implicit)
  local implicit_heatmap = implicit_resolved.heatmaps[1]
  eq(implicit_heatmap.sampled, true)
  eq(implicit_heatmap.vmin, 0)
  eq(implicit_heatmap.vmax, 1)
  local implicit_cells = Polar.heatmap_cells(implicit_heatmap, 272, 117, 73,
    2, 0, 1)
  eq(#implicit_cells, 2145)
  for _, cell in ipairs(implicit_cells) do
    assert(cell.color:match("^#%x%x%x%x%x%x$") ~= nil)
  end

  -- The SVG export and the live viewport paint exactly the sampled blocks.
  local svg = Format.scene_svg(scene, 600, 230)
  eq(count_plain(svg, 'class="scene-polar-heatmap-cell"'), 2145)
  contains(svg, 'class="scene-polar-heatmap"', "heatmap group")
  contains(svg, 'data-sampled="true"', "sampled marker")
  contains(svg, 'data-rows="65"', "source rows")
  contains(svg, 'data-row-span="2"', "block row span")
  local pass, calls = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 600, 230)
  eq(#named(calls, "polygon"), 2145)
end)

test("matches the cross-renderer large field fixture", function()
  local fixture = read_polar_fixture()
  local expected = fixture.large_field_expected
  local scene = fixture.large_field_scene
  scene.polar.heatmaps[1].values =
    large_field_scene(expected.rows, expected.cols).polar.heatmaps[1].values
  local resolved = Polar.resolve(scene)
  local heatmap = resolved.heatmaps[1]
  eq(heatmap.row_step, expected.row_step)
  eq(heatmap.col_step, expected.col_step)
  eq(heatmap.sampled_cells, expected.sampled_cells)
  eq(#heatmap.values, expected.sampled_rows)
  eq(#heatmap.values[1], expected.sampled_cols)

  local layout = fixture.field_layout
  local cx, cy, radius = Polar.frame_layout(52, 34, layout.width - 52,
    layout.height - 30, layout.has_colorbar)
  local cells = Polar.heatmap_cells(heatmap, cx, cy, radius, resolved.rmax,
    resolved.theta_zero, resolved.direction)
  eq(#cells, expected.sampled_cells)
  local first, last = cells[1], cells[#cells]
  local expected_first, expected_last = expected.first_cell, expected.last_cell
  eq(first.row, expected_first.row)
  eq(first.col, expected_first.col)
  eq(first.row_span, expected_first.row_span)
  eq(first.col_span, expected_first.col_span)
  near(first.inner_radius, expected_first.inner_radius)
  near(first.outer_radius, expected_first.outer_radius)
  near(first.start_angle, expected_first.start_angle)
  near(first.end_angle, expected_first.end_angle)
  eq(first.color, expected_first.color)
  eq(last.row, expected_last.row)
  eq(last.col, expected_last.col)
  eq(last.row_span, expected_last.row_span)
  eq(last.col_span, expected_last.col_span)
  near(last.inner_radius, expected_last.inner_radius)
  near(last.outer_radius, expected_last.outer_radius)
  near(last.start_angle, expected_last.start_angle)
  near(last.end_angle, expected_last.end_angle)
  eq(last.color, expected_last.color)

  -- Captions keep describing the source field, not the painted blocks.
  local summary = Format.scene_summary(scene)
  eq(summary.count, 1)
  eq(summary.points, expected.rows * expected.cols)
end)

test("collects quiver IR and projects local components", function()
  local resolved = Polar.resolve(quiver_scene())
  local quiver = resolved.series[1]
  eq(quiver.kind, "quiver")
  eq(quiver.count, 4)
  eq(quiver.drawn, 4)
  eq(quiver.stride, 1)
  eq(quiver.max_arrows, Polar.QUIVER_DEFAULT_MAX_ARROWS)
  eq(quiver.scale, 20)
  eq(quiver.auto_scale, false)
  eq(quiver.pivot, "tail")
  eq(quiver.normalize, false)
  eq(quiver.color, "#1f77b4")
  near(quiver.linewidth, 1.2)
  near(quiver.head, 5)

  local arrows = Polar.quiver_arrows(quiver, 300, 117, 73, 6, 0, 1)
  eq(#arrows, 4)
  local first = arrows[1]
  near(first.x, 336.5); near(first.y, 117)
  near(first.tail_x, 336.5); near(first.tail_y, 117)
  near(first.tip_x, 336.5); near(first.tip_y, 97)
  near(first.neck_x, 336.5); near(first.neck_y, 102)
  near(first.angle, -90)
  near(first.length, 20)
  near(first.head_x2, 338.75); near(first.head_y2, 102)
  near(first.head_x3, 334.25); near(first.head_y3, 102)
  eq(first.shaft, true)
  eq(first.headed, true)
  near(arrows[2].angle, -180)
  near(arrows[3].angle, 0)
  near(arrows[4].angle, 0)
end)

test("quiver follows theta_zero and clockwise direction", function()
  local scene = quiver_scene({
    theta_zero = math.pi / 2, theta_direction = "clockwise",
    theta = { 0, 0 }, r = { 3, 3 }, u = { 1, 0 }, v = { 0, 1 },
  })
  local resolved = Polar.resolve(scene)
  local arrows = Polar.quiver_arrows(resolved.series[1], 300, 117, 73, 6,
    resolved.theta_zero, resolved.direction)
  eq(#arrows, 2)
  -- At a north zero location a clockwise tangential arrow points east while
  -- the radial arrow points north.
  near(arrows[1].angle, 0)
  near(arrows[1].tip_x, 320)
  near(arrows[1].tip_y, 80.5)
  near(arrows[2].angle, -90)
  contains(Format.scene_svg(scene, 600, 230),
    'data-theta-direction="clockwise"', "clockwise export")
end)

test("quiver pivots and glyph length use SVG units", function()
  local function render(pivot)
    local scene = quiver_scene({
      theta = { 0 }, r = { 3 }, u = { 0 }, v = { 1 }, pivot = pivot,
    })
    local resolved = Polar.resolve(scene)
    return Polar.quiver_arrows(resolved.series[1], 300, 117, 73, 6, 0, 1)[1]
  end

  local tail = render("tail")
  near(tail.tail_x, 336.5)
  near(tail.tip_x, 356.5)
  near(tail.neck_x, 351.5)

  local middle = render("middle")
  near(middle.tail_x, 326.5)
  near(middle.tip_x, 346.5)

  local tip = render("tip")
  near(tip.tail_x, 316.5)
  near(tip.tip_x, 336.5)
  near(tip.length, 20)
  eq(tip.shaft, true)
end)

test("quiver automatic scaling and normalization match luaplotlib", function()
  local scene = quiver_scene({
    theta = { 0, 0 }, r = { 2, 2 }, u = { 1, 0 }, v = { 0, 2.5 },
  })
  scene.polar.series[1].scale = nil
  local resolved = Polar.resolve(scene)
  local quiver = resolved.series[1]
  eq(quiver.auto_scale, true)
  near(quiver.scale, 7.2)
  local arrows = Polar.quiver_arrows(quiver, 300, 117, 73, 6, 0, 1)
  near(arrows[1].magnitude, 1)
  near(arrows[1].length, 7.2)
  near(arrows[2].magnitude, 2.5)
  near(arrows[2].length, 18)

  local normalized = quiver_scene({
    theta = { 0, 0 }, r = { 2, 2 }, u = { 1, 0 }, v = { 0, 2.5 },
    normalize = true,
  })
  normalized.polar.series[1].scale = nil
  local normalized_resolved = Polar.resolve(normalized)
  near(normalized_resolved.series[1].scale, 18)
  local normalized_arrows = Polar.quiver_arrows(normalized_resolved.series[1],
    300, 117, 73, 6, 0, 1)
  near(normalized_arrows[1].magnitude, 1)
  near(normalized_arrows[2].magnitude, 1)
  near(normalized_arrows[1].length, 18)
  near(normalized_arrows[2].length, 18)
end)

test("decimates quiver arrows deterministically", function()
  local theta, u, v = {}, {}, {}
  for index = 1, 10 do
    theta[index] = 0
    u[index] = 1
    v[index] = 0
  end
  local scene = quiver_scene({ theta = theta, r = {}, u = u, v = v,
    max_arrows = 3 })
  for index = 1, 10 do scene.polar.series[1].r[index] = 3 end
  scene.polar.series[1].u[5] = 0
  local resolved = Polar.resolve(scene)
  local quiver = resolved.series[1]
  eq(quiver.count, 10)
  eq(quiver.max_arrows, 3)
  eq(quiver.stride, 4)
  eq(quiver.drawn, 2)
  local arrows = Polar.quiver_arrows(quiver, 300, 117, 73, 6, 0, 1)
  eq(#arrows, 2)
  eq(arrows[1].index, 1)
  eq(arrows[2].index, 9)
end)

test("exports and draws quiver arrows in series order", function()
  local scene = quiver_scene()
  scene.grid = false
  local svg = Format.scene_svg(scene, 600, 230)
  contains(svg, 'class="scene-polar-quiver"', "quiver group")
  contains(svg, 'data-count="4" data-drawn="4" data-stride="1" ' ..
    'data-max-arrows="512"', "quiver counters")
  contains(svg, 'data-scale="20.00" data-scale-mode="explicit"',
    "explicit scale")
  contains(svg, 'data-pivot="tail" data-normalize="false"',
    "quiver options")
  eq(count_plain(svg, 'class="scene-polar-quiver-arrow"'), 4)
  eq(count_plain(svg, 'class="scene-polar-quiver-shaft"'), 4)
  eq(count_plain(svg, 'class="scene-polar-quiver-head"'), 4)
  contains(svg, 'data-angle="-90.00"', "first arrow angle")
  contains(svg, 'data-angle="-180.00"', "second arrow angle")

  local pass, calls = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 600, 230)
  eq(#named(calls, "line"), 4)
  eq(#named(calls, "polygon"), 4)

  local summary = Format.scene_summary(scene)
  eq(summary.count, 1)
  eq(summary.series[1].kind, "quiver")
  eq(summary.points, 4)
end)

test("tolerates malformed and empty quiver data", function()
  local scene = {
    type = "luaplotlib", orientation = "polar", grid = false,
    polar = {
      rmax = 6,
      series = {
        { kind = "quiver", theta = { 0 / 0, 0 }, r = { 3, 4 },
          u = { 1, 1 }, v = { 0, 0 },
          max_arrows = 0,
          style = { linewidth = -1, head = -2, color = "#ff7f0e" } },
        { kind = "quiver", theta = { 0 }, r = { 2 } },
      },
    },
  }
  local resolved = Polar.resolve(scene)
  eq(#resolved.series, 2)
  local first = resolved.series[1]
  eq(first.kind, "quiver")
  eq(first.max_arrows, Polar.QUIVER_DEFAULT_MAX_ARROWS)
  eq(first.stride, 1)
  eq(first.drawn, 1)
  eq(first.linewidth, 0)
  eq(first.head, 0)
  local second = resolved.series[2]
  eq(second.drawn, 0)
  eq(second.count, 1)
  eq(resolved.rmax, 6)

  local svg = Format.scene_svg(scene, 600, 230)
  eq(count_plain(svg, 'class="scene-polar-quiver"'), 2)
  eq(count_plain(svg, 'class="scene-polar-quiver-shaft"'), 0)
  eq(count_plain(svg, 'class="scene-polar-quiver-head"'), 0)

  local pass, calls = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 600, 230)
  eq(#named(calls, "line"), 0)
  eq(#named(calls, "polygon"), 0)
end)

test("matches the cross-renderer quiver fixture", function()
  local fixture = read_polar_fixture()
  local expected = fixture.quiver_expected
  local scene = fixture.quiver_scene
  local resolved = Polar.resolve(scene)
  local quiver = resolved.series[1]
  eq(quiver.kind, "quiver")
  eq(quiver.count, expected.count)
  eq(quiver.drawn, expected.drawn)
  eq(quiver.stride, expected.stride)
  eq(quiver.max_arrows, expected.max_arrows)
  near(quiver.scale, expected.scale)
  eq(quiver.auto_scale, expected.scale_mode == "auto")
  eq(quiver.pivot, expected.pivot)

  local layout = fixture.layout
  local cx, cy, radius = Polar.frame_layout(52, 34, layout.width - 52,
    layout.height - 30, false)
  eq(cx, layout.cx)
  eq(cy, layout.cy)
  eq(radius, layout.radius)
  local arrows = Polar.quiver_arrows(quiver, cx, cy, radius, resolved.rmax,
    resolved.theta_zero, resolved.direction)
  eq(#arrows, #expected.arrows)
  for index, arrow in ipairs(arrows) do
    local want = expected.arrows[index]
    eq(arrow.index, want.index)
    near(arrow.angle, want.angle, 1e-9, "quiver angle")
    near(arrow.magnitude, want.magnitude, 1e-9, "quiver magnitude")
    near(arrow.tail_x, want.tail_x, 1e-9, "quiver tail x")
    near(arrow.tail_y, want.tail_y, 1e-9, "quiver tail y")
    near(arrow.tip_x, want.tip_x, 1e-9, "quiver tip x")
    near(arrow.tip_y, want.tip_y, 1e-9, "quiver tip y")
    near(arrow.neck_x, want.neck_x, 1e-9, "quiver neck x")
    near(arrow.neck_y, want.neck_y, 1e-9, "quiver neck y")
  end
end)

test("collects streamplot IR and projects streamline geometry", function()
  local resolved = Polar.resolve(stream_scene({ step = 0.06 }))
  local stream = resolved.series[1]
  eq(stream.kind, "streamplot")
  eq(stream.cols, 5)
  eq(stream.rows, 4)
  eq(stream.line_count, 2)
  eq(stream.point_count, 7)
  eq(stream.arrow_count, 2)
  near(stream.step, 0.06)
  eq(stream.step_mode, "explicit")
  eq(stream.periodic, true)
  eq(stream.truncated, false)
  eq(stream.density, 1)
  eq(stream.max_steps, 300)
  eq(stream.max_lines, 64)
  eq(stream.max_points, 8000)
  eq(stream.arrows, true)
  near(stream.head, 6)
  near(stream.linewidth, 1.5)
  near(stream.alpha, 0.9)

  local lines = Polar.stream_lines(stream, 300, 117, 73, 2, 0, 1)
  eq(#lines, 2)
  local first = lines[1]
  eq(#first.points, 3)
  eq(#first.arrows, 1)
  near(first.points[1].x, 336.5)
  near(first.points[1].y, 117)
  near(first.points[2].x, 338.43811621079834, 1e-9)
  near(first.points[2].y, 96.0011614091359, 1e-9)
  near(first.points[3].x, 327.60944782986195, 1e-9)
  near(first.arrows[1].x, 338.43811621079834, 1e-9)
  near(first.arrows[1].tip_x, 341.03619242215166, 1e-9)
  near(first.arrows[1].head_y2, 99.83942999935388, 1e-9)
  near(first.arrows[1].head_x3, 334.490039999445, 1e-9)
  near(first.arrows[1].head_y3, 95.16289281891792, 1e-9)

  -- Captions count integrated polyline points, not the value-grid cells.
  eq(Format.scene_summary(stream_scene({ step = 0.06 })).points, 7)
end)

test("streamplot follows theta_zero and clockwise direction", function()
  local scene = stream_scene({
    theta_zero = math.pi / 2, theta_direction = "clockwise",
    theta = { 0, 0 }, r = { 2, 2 },
    lines = { { theta = { 0, 0 }, r = { 2, 2 },
      arrows = { { theta = 0, r = 2, angle = 0 } } } },
  })
  local resolved = Polar.resolve(scene)
  local lines = Polar.stream_lines(resolved.series[1], 300, 117, 73, 2,
    resolved.theta_zero, resolved.direction)
  eq(#lines, 1)
  near(lines[1].points[1].x, 300)
  near(lines[1].points[1].y, 44)
  near(lines[1].points[2].x, 300)
  near(lines[1].points[2].y, 44)
  local arrow = lines[1].arrows[1]
  near(arrow.x, 300)
  near(arrow.y, 44)
  near(arrow.head_x1, 303)
  near(arrow.head_y1, 44)
  near(arrow.head_y2, 46.7)
  near(arrow.head_y3, 41.3)
  contains(Format.scene_svg(scene, 600, 230),
    'data-theta-direction="clockwise"', "clockwise streamplot export")
end)

test("streamplot derives auto step and tolerates malformed lines", function()
  local auto = Polar.resolve(stream_scene({
    theta = { 0, 2 * math.pi }, r = { 0, 2 },
  })).series[1]
  near(auto.step, 0.08)
  eq(auto.step_mode, "auto")
  eq(auto.periodic, true)
  near(auto.head, 6)
  near(auto.linewidth, 1.5)

  local explicit = Polar.resolve(stream_scene({ step = 0.1 })).series[1]
  near(explicit.step, 0.1)
  eq(explicit.step_mode, "explicit")

  local malformed = stream_scene({
    head = -2,
    lines = {
      { theta = { 0, 0 / 0, 1 }, r = { 1, 1.5, 2 },
        arrows = {
          { theta = 0, r = 1, angle = 0 },
          { theta = 0 / 0, r = 1, angle = 0 },
        } },
      { theta = { 0 }, r = { 1 } },
      "not a line",
    },
  })
  local resolved = Polar.resolve(malformed)
  local stream = resolved.series[1]
  eq(stream.line_count, 1)
  eq(stream.point_count, 2)
  eq(stream.arrow_count, 0)
  eq(#stream.lines[1].arrows, 0)
  local lines = Polar.stream_lines(stream, 300, 117, 73, 2, 0, 1)
  eq(#lines, 1)
  eq(#lines[1].points, 2)
  eq(#lines[1].arrows, 0)

  local svg = Format.scene_svg(malformed, 600, 230)
  eq(count_plain(svg, 'class="scene-polar-streamline-path"'), 1)
  eq(count_plain(svg, 'class="scene-polar-stream-arrow"'), 0)
end)

test("exports streamplot groups and draws the live geometry", function()
  local scene = stream_scene({ step = 0.06 })
  scene.grid = false
  local svg = Format.scene_svg(scene, 600, 230)
  eq(count_plain(svg, 'class="scene-polar-streamplot"'), 1)
  eq(count_plain(svg, 'class="scene-polar-streamline"'), 2)
  eq(count_plain(svg, 'class="scene-polar-streamline-path"'), 2)
  eq(count_plain(svg, 'class="scene-polar-stream-arrow"'), 2)
  contains(svg, 'data-cols="5"', "stream cols")
  contains(svg, 'data-rows="4"', "stream rows")
  contains(svg, 'data-lines="2"', "stream lines")
  contains(svg, 'data-points="7"', "stream points")
  contains(svg, 'data-arrow-count="2"', "stream arrows")
  contains(svg, 'data-step="0.06"', "stream step")
  contains(svg, 'data-step-mode="explicit"', "stream step mode")
  contains(svg, 'data-density="1.00"', "stream density")
  contains(svg, 'data-max-steps="300"', "stream max steps")
  contains(svg, 'data-max-lines="64"', "stream max lines")
  contains(svg, 'data-max-points="8000"', "stream max points")
  contains(svg, 'data-arrows="true"', "stream arrows enabled")
  contains(svg, 'data-head="6.00"', "stream head")
  contains(svg, 'data-periodic="true"', "stream periodic")
  contains(svg, 'data-truncated="false"', "stream truncation")
  contains(svg, 'stroke-opacity="0.90"', "stream stroke alpha")
  contains(svg, 'fill-opacity="0.90"', "stream fill alpha")

  local pass, calls = new_pass()
  Plot.draw(pass, {}, scene, 0, 0, 600, 230)
  eq(#named(calls, "line"), 5)
  eq(#named(calls, "polygon"), 2)
end)

test("matches the cross-renderer streamplot fixture", function()
  local fixture = read_polar_fixture()
  local expected = fixture.streamplot_expected
  local scene = fixture.streamplot_scene
  local resolved = Polar.resolve(scene)
  local stream = resolved.series[1]
  eq(stream.kind, "streamplot")
  eq(stream.cols, expected.cols)
  eq(stream.rows, expected.rows)
  eq(stream.line_count, expected.lines)
  eq(stream.point_count, expected.points)
  eq(stream.arrow_count, expected.arrow_count)
  near(stream.step, expected.step)
  eq(stream.step_mode, expected.step_mode)
  eq(stream.density, expected.density)
  eq(stream.max_steps, expected.max_steps)
  eq(stream.max_lines, expected.max_lines)
  eq(stream.max_points, expected.max_points)
  eq(stream.periodic, expected.periodic)
  eq(stream.truncated, expected.truncated)
  eq(stream.arrows, expected.arrows)
  near(stream.head, expected.head)
  near(stream.linewidth, expected.linewidth)
  near(stream.alpha, expected.alpha)
  eq(stream.color, expected.color)

  local layout = fixture.layout
  local cx, cy, radius = Polar.frame_layout(52, 34, layout.width - 52,
    layout.height - 30, false)
  eq(cx, layout.cx)
  eq(cy, layout.cy)
  eq(radius, layout.radius)
  local lines = Polar.stream_lines(stream, cx, cy, radius, resolved.rmax,
    resolved.theta_zero, resolved.direction)
  eq(#lines, #expected.line_points)
  for line_index, line in ipairs(lines) do
    local want_line = expected.line_points[line_index]
    eq(#line.points, #want_line)
    for point_index, point in ipairs(line.points) do
      local want = want_line[point_index]
      near(point.x, want.x, 1e-9, "stream point x")
      near(point.y, want.y, 1e-9, "stream point y")
      near(point.theta, want.theta, 1e-9, "stream point theta")
      near(point.r, want.r, 1e-9, "stream point r")
    end
  end
  local arrow_index = 0
  for _, line in ipairs(lines) do
    for _, arrow in ipairs(line.arrows) do
      arrow_index = arrow_index + 1
      local want = expected.arrow_points[arrow_index]
      near(arrow.x, want.x, 1e-9, "stream arrow x")
      near(arrow.y, want.y, 1e-9, "stream arrow y")
      near(arrow.theta, want.theta, 1e-9, "stream arrow theta")
      near(arrow.r, want.r, 1e-9, "stream arrow r")
      near(arrow.angle, want.angle, 1e-9, "stream arrow angle")
      near(arrow.head_x1, want.head_x1, 1e-9, "stream arrow tip x")
      near(arrow.head_y1, want.head_y1, 1e-9, "stream arrow tip y")
      near(arrow.head_x2, want.head_x2, 1e-9, "stream arrow left x")
      near(arrow.head_y2, want.head_y2, 1e-9, "stream arrow left y")
      near(arrow.head_x3, want.head_x3, 1e-9, "stream arrow right x")
      near(arrow.head_y3, want.head_y3, 1e-9, "stream arrow right y")
    end
  end
  eq(arrow_index, #expected.arrow_points)
end)

print(string.format("\npolar tests: %d passed, %d failed", passed, failed))
if failed > 0 then
  io.stderr:write(table.concat(failures, "\n") .. "\n")
  os.exit(1)
end
