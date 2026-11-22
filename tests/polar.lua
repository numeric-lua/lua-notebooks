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

print(string.format("\npolar tests: %d passed, %d failed", passed, failed))
if failed > 0 then
  io.stderr:write(table.concat(failures, "\n") .. "\n")
  os.exit(1)
end
