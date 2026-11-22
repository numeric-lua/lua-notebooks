--
-- LÖVR renderer for renderer-agnostic luaplotlib scenes.
--
-- The scene table is produced by luaplotlib.scene.from_figure or by a kernel.
-- This pure-Lua renderer draws in the notebook's 2D pixel space; it does not
-- need a graphics context inside the kernel.  Polar geometry is shared with
-- the static HTML export through notebook/polar.lua so both backends agree on
-- rmax, ticks, sampling, labels, and bar wedges.
--
local Theme = require("ui.theme")
local Polar = require("notebook.polar")
local Plot = {}

local function color(hex, alpha)
  if type(hex) ~= "string" then
    return 0.5, 0.7, 1.0, alpha or 1
  end
  local r, g, b
  if hex:match("^#%x%x%x%x%x%x$") then
    r = tonumber(hex:sub(2, 3), 16) / 255
    g = tonumber(hex:sub(4, 5), 16) / 255
    b = tonumber(hex:sub(6, 7), 16) / 255
  elseif hex:match("^#%x%x%x$") then
    r = tonumber(hex:sub(2, 2), 16) / 15
    g = tonumber(hex:sub(3, 3), 16) / 15
    b = tonumber(hex:sub(4, 4), 16) / 15
  else
    r, g, b = 0.5, 0.7, 1.0
  end
  return r, g, b, alpha or 1
end

local function set_color(pass, style)
  style = style or {}
  local r, g, b, a = color(style.color, style.alpha)
  pass:setColor(r, g, b, a)
end

local function text(pass, font, value, x, y, scale, halign, valign, style)
  set_color(pass, style)
  pass:setFont(font)
  pass:text(value, x, y, 0, scale or 0.75, 0, 0, 1, 0, 0,
    halign or "left", valign or "top")
end

local function finite_range(lo, hi)
  if type(lo) ~= "number" or type(hi) ~= "number" or lo == hi then
    return 0, 1
  end
  return lo, hi
end

function Plot.draw(pass, font, scene, x, y, w, h)
  scene = scene or {}
  if type(scene) == "table" and scene.orientation == "polar" then
    return Plot.draw_polar(pass, font, scene, x, y, w, h)
  end
  local light = Theme.mode == "light"
  local xmin, xmax = finite_range(scene.xlim and scene.xlim[1],
    scene.xlim and scene.xlim[2])
  local ymin, ymax = finite_range(scene.ylim and scene.ylim[1],
    scene.ylim and scene.ylim[2])
  local left = x + 58
  local right = x + w - 18
  local top = y + 40
  local bottom = y + h - 36
  local plot_w = math.max(1, right - left)
  local plot_h = math.max(1, bottom - top)

  local function sx(value)
    return left + (value - xmin) / (xmax - xmin) * plot_w
  end
  local function sy(value)
    return bottom - (value - ymin) / (ymax - ymin) * plot_h
  end

  -- Background and plot region.
  if light then
    pass:setColor(0.97, 0.975, 0.99, 1)
  else
    pass:setColor(0.025, 0.03, 0.05, 1)
  end
  pass:plane(x + w / 2, y + h / 2, 0, w, h)
  if light then
    pass:setColor(1, 1, 1, 1)
  else
    pass:setColor(0.055, 0.065, 0.09, 1)
  end
  pass:plane(left + plot_w / 2, top + plot_h / 2, 0, plot_w, plot_h)

  if scene.grid then
    if light then
      pass:setColor(0.84, 0.86, 0.90, 1)
    else
      pass:setColor(0.15, 0.17, 0.23, 1)
    end
    for index = 1, 4 do
      local fraction = index / 5
      local gx = left + plot_w * fraction
      pass:line(gx, top, 0, gx, bottom, 0)
      local gy = top + plot_h * fraction
      pass:line(left, gy, 0, right, gy, 0)
    end
  end

  -- Axes.
  if light then
    pass:setColor(0.38, 0.42, 0.50, 1)
  else
    pass:setColor(0.45, 0.5, 0.62, 1)
  end
  pass:line(left, top, 0, left, bottom, 0)
  pass:line(left, bottom, 0, right, bottom, 0)

  -- Simple numeric ticks (categories replace horizontal labels when present).
  local tick_color = light and "#5b6472" or "#7f879a"
  local title_color = light and "#202630" or "#e8ecff"
  local label_color = light and "#4a5260" or "#aeb6c8"
  local category = scene.category_ticks
  for index = 0, 4 do
    local fraction = index / 4
    local tx = left + plot_w * fraction
    local ty = top + plot_h * fraction
    local xvalue = xmin + (xmax - xmin) * fraction
    local yvalue = ymax - (ymax - ymin) * fraction
    if not category then
      text(pass, font, string.format("%.4g", xvalue), tx, bottom + 6, 0.6,
        "center", "top", { color = tick_color })
    end
    text(pass, font, string.format("%.4g", yvalue), left - 8, ty, 0.6,
      "right", "middle", { color = tick_color })
  end
  if category then
    for _, tick in ipairs(category) do
      text(pass, font, tostring(tick.label), sx(tick.position), bottom + 6, 0.58,
        "center", "top", { color = tick_color })
    end
  end

  -- Series.
  for _, series in ipairs(scene.series or {}) do
    set_color(pass, series.style)
    if series.kind == "line" then
      for index = 2, #series.x do
        pass:line(sx(series.x[index - 1]), sy(series.y[index - 1]), 0,
          sx(series.x[index]), sy(series.y[index]), 0)
      end
      if series.style and series.style.marker and #series.x <= 200 then
        for index = 1, #series.x do
          pass:circle(sx(series.x[index]), sy(series.y[index]), 0,
            series.style.markersize or 3)
        end
      end
    elseif series.kind == "scatter" then
      local radius = series.style and (series.style.radius or
        series.style.markersize) or 4
      for index = 1, #series.x do
        pass:circle(sx(series.x[index]), sy(series.y[index]), 0, radius)
      end
    elseif series.kind == "bar" then
      local baseline = math.max(0, ymin)
      for index = 1, #series.x do
        local value = series.y[index]
        local x0 = sx(series.x[index] - series.width / 2)
        local x1 = sx(series.x[index] + series.width / 2)
        local y0 = sy(baseline)
        local y1 = sy(value)
        local bar_h = math.abs(y1 - y0)
        pass:plane((x0 + x1) / 2, (y0 + y1) / 2, 0, math.max(1, x1 - x0),
          math.max(1, bar_h))
      end
    elseif series.kind == "hist" then
      for index = 1, #series.counts do
        if series.edges[index] == nil or series.edges[index + 1] == nil then
          break
        end
        local x0 = sx(series.edges[index])
        local x1 = sx(series.edges[index + 1])
        local y0 = sy(math.max(0, ymin))
        local y1 = sy(series.counts[index])
        pass:plane((x0 + x1) / 2, (y0 + y1) / 2, 0, math.max(1, x1 - x0),
          math.max(1, math.abs(y1 - y0)))
      end
    end
  end

  -- Labels.
  if scene.title then
    text(pass, font, scene.title, x + 10, y + 10, 0.82, "left", "top",
      { color = title_color })
  end
  if scene.xlabel then
    text(pass, font, scene.xlabel, left + plot_w / 2, y + h - 18, 0.65,
      "center", "middle", { color = label_color })
  end
  if scene.ylabel then
    text(pass, font, scene.ylabel, x + 12, top + plot_h / 2, 0.65,
      "center", "middle", { color = label_color })
  end
end

-- The polar frame keeps a little room for theta labels, which sit outside the
-- circle.  The radius formula is shared with the SVG preview.  A scene with a
-- colourbar reserves the bar column before fitting the circle.
function Plot.polar_layout(x, y, w, h, has_colorbar)
  local left = x + 52
  local right = x + w - 52
  local top = y + 34
  local bottom = y + h - 30
  return Polar.frame_layout(left, top, right, bottom, has_colorbar)
end

-- Flat polygon points for one annular cell part.  The centre-first form is
-- used for pie-like cells whose inner radius is zero.
local function polar_cell_points(cell, part, cx, cy)
  local points = {}
  local start_angle, end_angle = part.start_angle, part.end_angle
  local span = math.abs(end_angle - start_angle)
  local steps = math.max(2, math.ceil(span / (math.pi / 24)))
  if cell.inner_radius <= 0.0005 then
    points[1], points[2], points[3] = cx, cy, 0
  end
  for index = 0, steps do
    local angle = start_angle + (end_angle - start_angle) * index / steps
    points[#points + 1] = cx + cell.outer_radius * math.cos(angle)
    points[#points + 1] = cy - cell.outer_radius * math.sin(angle)
    points[#points + 1] = 0
  end
  if cell.inner_radius > 0.0005 then
    for index = steps, 0, -1 do
      local angle = start_angle + (end_angle - start_angle) * index / steps
      points[#points + 1] = cx + cell.inner_radius * math.cos(angle)
      points[#points + 1] = cy - cell.inner_radius * math.sin(angle)
      points[#points + 1] = 0
    end
  end
  return points
end

local function draw_polar_fields(pass, font, resolved, cx, cy, radius)
  local heat_cells = 0
  for _, heatmap in ipairs(resolved.heatmaps) do
    for _, cell in ipairs(Polar.heatmap_cells(heatmap, cx, cy, radius,
        resolved.rmax, resolved.theta_zero, resolved.direction)) do
      set_color(pass, { color = cell.color, alpha = cell.alpha })
      if cell.full_disc then
        pass:circle(cx, cy, 0, cell.outer_radius)
      else
        for _, part in ipairs(cell.parts) do
          pass:polygon(polar_cell_points(cell, part, cx, cy))
        end
      end
      heat_cells = heat_cells + 1
    end
  end

  for _, contour in ipairs(resolved.contours) do
    set_color(pass, contour.style)
    for _, level in ipairs(contour.levels) do
      for _, segment in ipairs(level.segments) do
        local points = Polar.contour_segment_points(contour, segment, cx, cy,
          radius, resolved.rmax, resolved.theta_zero, resolved.direction)
        for index = 2, #points do
          pass:line(points[index - 1][1], points[index - 1][2], 0,
            points[index][1], points[index][2], 0)
        end
      end
      local label = Polar.contour_label(contour, level, cx, cy, radius,
        resolved.rmax, resolved.theta_zero, resolved.direction)
      if label ~= nil then
        text(pass, font, label.text, label.x, label.y, 0.55, "center",
          "middle", { color = contour.style.color })
      end
    end
  end
  return heat_cells
end

local function draw_polar_colorbar(pass, font, colorbar, cx, cy, radius)
  if colorbar == nil then return end
  local x, y, width, height = Polar.colorbar_layout(cx, cy, radius)
  local tick_color = Theme.mode == "light" and "#5b6472" or "#7f879a"
  local frame_color = Theme.mode == "light" and "#616a7a" or "#42506a"

  for _, step in ipairs(Polar.colorbar_steps(colorbar)) do
    local top = y + height * step.y0
    local bottom = y + height * step.y1
    set_color(pass, { color = step.color, alpha = 1 })
    pass:plane(x + width / 2, (top + bottom) / 2, 0, width,
      math.max(1, bottom - top))
  end

  set_color(pass, { color = frame_color })
  pass:line(x, y, 0, x + width, y, 0)
  pass:line(x + width, y, 0, x + width, y + height, 0)
  pass:line(x + width, y + height, 0, x, y + height, 0)
  pass:line(x, y + height, 0, x, y, 0)

  local ticks = Polar.colorbar_ticks(colorbar)
  local max_label = 0
  for _, tick in ipairs(ticks) do
    local tick_y = y + height * (1 - tick.fraction)
    pass:line(x + width, tick_y, 0, x + width + 4, tick_y, 0)
    if tick.label ~= nil then
      text(pass, font, tick.label, x + width + 8, tick_y + 3.5, 0.62,
        "left", "middle", { color = tick_color })
      max_label = math.max(max_label, #tick.label * 5.5)
    end
  end

  if colorbar.label ~= nil then
    local title_x = x + width + 8 + max_label + 14
    set_color(pass, { color = tick_color })
    pass:setFont(font)
    pass:text(colorbar.label, title_x, y + height / 2, 0, 0.65,
      -math.pi / 2, 0, 0, 1, 0, "center", "middle")
  end
end

-- Draw a luaplotlib polar scene.  The static export and this function consume
-- the same resolved IR and the same projection helpers.  Heatmaps and
-- contours are painted beneath the line/scatter/bar series; the colourbar is
-- painted last, outside the frame.
function Plot.draw_polar(pass, font, scene, x, y, w, h)
  scene = scene or {}
  local light = Theme.mode == "light"
  local resolved = Polar.resolve(scene)
  local rmax = resolved.rmax
  local theta_zero = resolved.theta_zero
  local direction = resolved.direction
  local cx, cy, radius = Plot.polar_layout(x, y, w, h,
    resolved.colorbar ~= nil)
  local rings = Polar.rings(resolved.polar, rmax)
  local spokes = Polar.spokes(resolved.polar)

  local tick_color = light and "#5b6472" or "#7f879a"
  local title_color = light and "#202630" or "#e8ecff"
  local label_color = light and "#4a5260" or "#aeb6c8"

  -- Background.  The export draws the circular frame directly on the scene
  -- background, so the live renderer does the same.
  if light then
    pass:setColor(0.97, 0.975, 0.99, 1)
  else
    pass:setColor(0.025, 0.03, 0.05, 1)
  end
  pass:plane(x + w / 2, y + h / 2, 0, w, h)

  if scene.grid ~= false then
    if light then
      pass:setColor(0.84, 0.86, 0.90, 1)
    else
      pass:setColor(0.15, 0.17, 0.23, 1)
    end
    for _, tick in ipairs(rings) do
      pass:circle(cx, cy, 0, radius * tick.value / rmax, 0, 0, 1, 0, "line")
    end
    for _, tick in ipairs(spokes) do
      local angle = theta_zero + direction * tick.value
      pass:line(cx, cy, 0, cx + radius * math.cos(angle),
        cy - radius * math.sin(angle), 0)
    end
  end

  -- Heatmap cells and contour isolines sit under the frame and series.
  draw_polar_fields(pass, font, resolved, cx, cy, radius)

  -- Frame.
  if light then
    pass:setColor(0.38, 0.42, 0.50, 1)
  else
    pass:setColor(0.45, 0.5, 0.62, 1)
  end
  pass:circle(cx, cy, 0, radius, 0, 0, 1, 0, "line")

  -- Tick labels use the same short-label policy as the SVG preview.
  if scene.grid ~= false then
    for _, tick in ipairs(rings) do
      local label = Polar.radius_label(tick)
      if label ~= nil then
        local ring_radius = radius * tick.value / rmax
        local label_x, label_y = Polar.ring_label_position(cx, cy, ring_radius)
        text(pass, font, label, label_x, label_y, 0.55, "right", "middle",
          { color = tick_color })
      end
    end
    for _, tick in ipairs(spokes) do
      local label = Polar.theta_label(tick)
      if label ~= nil then
        local angle = theta_zero + direction * tick.value
        local label_x, label_y = Polar.theta_label_position(cx, cy, radius,
          angle)
        text(pass, font, label, label_x, label_y, 0.55, "center", "middle",
          { color = tick_color })
      end
    end
  end

  -- Series.
  for _, series in ipairs(resolved.series) do
    local base_style = { color = series.color, alpha = series.alpha }
    if series.points ~= nil then
      if series.kind == "line" then
        set_color(pass, base_style)
        local step = Polar.sample_step(#series.points,
          Polar.LINE_SAMPLE_LIMIT)
        local previous_x, previous_y
        for index = 1, #series.points, step do
          local point = series.points[index]
          local point_x, point_y = Polar.project(cx, cy, radius, rmax,
            theta_zero, direction, point.theta, point.r)
          if previous_x ~= nil then
            pass:line(previous_x, previous_y, 0, point_x, point_y, 0)
          end
          previous_x, previous_y = point_x, point_y
        end
      else
        local step = Polar.sample_step(#series.points,
          Polar.SCATTER_SAMPLE_LIMIT)
        for index = 1, #series.points, step do
          local point = series.points[index]
          local point_x, point_y = Polar.project(cx, cy, radius, rmax,
            theta_zero, direction, point.theta, point.r)
          if point.color ~= nil then
            set_color(pass, { color = point.color, alpha = series.alpha })
          else
            set_color(pass, base_style)
          end
          pass:circle(point_x, point_y, 0, Polar.point_radius(point))
        end
      end
    elseif series.bars ~= nil then
      local step = Polar.sample_step(#series.bars, Polar.BAR_SAMPLE_LIMIT)
      for index = 1, #series.bars, step do
        local bar = series.bars[index]
        for _, sector in ipairs(Polar.bar_sectors(bar, radius, rmax,
            theta_zero, direction)) do
          set_color(pass, {
            color = sector.color or series.color,
            alpha = series.alpha,
          })
          if sector.full then
            pass:circle(cx, cy, 0, sector.radius)
          else
            pass:polygon(Polar.sector_points(cx, cy, sector))
          end
        end
      end
    elseif series.arrows ~= nil then
      -- Quiver arrows are already decimated and sized by notebook/polar.lua.
      -- Draw the shaft first, then the filled head triangle, in series order.
      set_color(pass, base_style)
      for _, arrow in ipairs(Polar.quiver_arrows(series, cx, cy, radius,
          rmax, theta_zero, direction)) do
        if arrow.shaft then
          pass:line(arrow.tail_x, arrow.tail_y, 0, arrow.neck_x,
            arrow.neck_y, 0)
        end
        if arrow.headed then
          pass:polygon({
            arrow.head_x1, arrow.head_y1, 0,
            arrow.head_x2, arrow.head_y2, 0,
            arrow.head_x3, arrow.head_y3, 0,
          })
        end
      end
    end
  end

  draw_polar_colorbar(pass, font, resolved.colorbar, cx, cy, radius)

  -- Labels.
  if scene.title then
    text(pass, font, scene.title, x + 10, y + 10, 0.82, "left", "top",
      { color = title_color })
  end
  if scene.xlabel then
    text(pass, font, scene.xlabel, cx, y + h - 14, 0.65, "center", "middle",
      { color = label_color })
  end
  if scene.ylabel then
    text(pass, font, scene.ylabel, x + 14, cy, 0.65, "center", "middle",
      { color = label_color })
  end
end

return Plot
