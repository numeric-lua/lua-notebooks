--
-- LÖVR renderer for renderer-agnostic luaplotlib scenes.
--
-- The scene table is produced by luaplotlib.scene.from_figure or by a kernel.
-- This renderer is intentionally dependency-free and draws in the notebook's
-- 2D pixel space; it does not need a graphics context inside the kernel.
--
local Theme = require("ui.theme")
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

return Plot
