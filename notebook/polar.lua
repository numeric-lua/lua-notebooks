--
-- Shared geometry for luaplotlib polar scenes.
--
-- The live viewport (ui/plot.lua) and the static HTML export
-- (notebook/format.lua) draw the same renderer-agnostic IR.  Keeping the
-- projection, tick fallbacks, sampling caps, label limits, and bar wedges in
-- one dependency-free module is what keeps the two renderers in parity.
--
-- All angles are radians.  Screen coordinates are y-down, so a positive
-- `theta_direction` maps to counterclockwise motion on screen through the
-- `cy - radius * sin(angle)` projection.
--
local Polar = {}

Polar.PALETTE = {
  "#4c78a8", "#f58518", "#54a24b", "#b279a2", "#e45756", "#72b7b2",
}

Polar.LINE_SAMPLE_LIMIT = 800
Polar.SCATTER_SAMPLE_LIMIT = 400
Polar.BAR_SAMPLE_LIMIT = 400
Polar.RADIUS_LABEL_LIMIT = 12
Polar.THETA_LABEL_LIMIT = 18
Polar.THETA_LABEL_GAP = 12
Polar.DEFAULT_BAR_WIDTH = 0.2
Polar.DEFAULT_POINT_RADIUS = 2.6
Polar.MAX_POINT_RADIUS = 8
Polar.MIN_POINT_RADIUS = 1

local pi = math.pi

local function finite_number(value)
  return type(value) == "number" and value == value and
    value ~= math.huge and value ~= -math.huge
end

local function valid_color(value)
  if type(value) ~= "string" then return nil end
  if value:match("^#%x%x%x%x%x%x$") or value:match("^#%x%x%x$") then
    return value
  end
  return nil
end

Polar.finite_number = finite_number
Polar.valid_color = valid_color

-- Pull the polar options out of a scene, mirroring the IR emitted by
-- luaplotlib's polar backend.  An explicit `rmax` must be positive; otherwise
-- the caller falls back to the largest observed radius.
function Polar.config(scene)
  local polar = type(scene) == "table" and type(scene.polar) == "table" and
    scene.polar or {}
  local rmax = finite_number(polar.rmax) and polar.rmax > 0 and polar.rmax or
    nil
  local theta_zero = finite_number(polar.theta_zero) and polar.theta_zero or 0
  local direction = polar.theta_direction == "clockwise" and -1 or 1
  return polar, rmax, theta_zero, direction
end

-- Map the polar scene IR into the compact point/bar shapes both renderers use.
-- The observed maximum absolute radius is returned for scenes that omit
-- `polar.rmax`.  We copy the values so the renderers never mutate kernel data.
function Polar.collect(scene)
  local polar = type(scene) == "table" and type(scene.polar) == "table" and
    scene.polar or {}
  local collected, observed, palette_index = {}, 0, 0

  local function note(value)
    if finite_number(value) then
      local magnitude = math.abs(value)
      if magnitude > observed then observed = magnitude end
    end
  end

  for _, item in ipairs(polar.series or {}) do
    if type(item) == "table" then
      local style = type(item.style) == "table" and item.style or {}
      local color = valid_color(style.color)
      if color == nil then
        palette_index = palette_index + 1
        color = Polar.PALETTE[(palette_index - 1) % #Polar.PALETTE + 1]
      end
      local alpha = finite_number(style.alpha) and style.alpha or 1
      local theta, r = item.theta, item.r
      if type(theta) == "table" and type(r) == "table" then
        local count = math.min(#theta, #r)
        if item.kind == "bar" then
          local widths = type(item.widths) == "table" and item.widths or nil
          local colors = type(item.colors) == "table" and item.colors or nil
          local bars = {}
          for index = 1, count do
            if finite_number(theta[index]) and finite_number(r[index]) then
              note(r[index])
              local width = Polar.DEFAULT_BAR_WIDTH
              if widths and finite_number(widths[index]) then
                width = math.max(0.001, widths[index])
              end
              local bar_color = colors and valid_color(colors[index]) or nil
              bars[#bars + 1] = {
                theta = theta[index], r = r[index], width = width,
                color = bar_color or color,
              }
            end
          end
          if #bars > 0 then
            collected[#collected + 1] = {
              kind = "bar", bars = bars, color = color, alpha = alpha,
            }
          end
        else
          local radii = type(item.radii) == "table" and item.radii or nil
          local colors = type(item.colors) == "table" and item.colors or nil
          local style_radius = finite_number(style.radius) and style.radius or
            nil
          local points = {}
          for index = 1, count do
            if finite_number(theta[index]) and finite_number(r[index]) then
              note(r[index])
              local point_radius = style_radius
              if radii and finite_number(radii[index]) then
                point_radius = radii[index]
              end
              points[#points + 1] = {
                theta = theta[index],
                r = r[index],
                radius = point_radius,
                color = colors and valid_color(colors[index]) or nil,
              }
            end
          end
          if #points > 0 then
            collected[#collected + 1] = {
              kind = item.kind == "scatter" and "scatter" or "line",
              points = points, color = color, alpha = alpha,
            }
          end
        end
      end
    end
  end
  return collected, observed
end

-- Resolve everything the renderers need in one place: the axis options, the
-- effective rmax (explicit or observed), and the filtered series.
function Polar.resolve(scene)
  local polar, rmax, theta_zero, direction = Polar.config(scene)
  local collected, observed = Polar.collect(scene)
  local heatmaps = Polar.collect_heatmaps(polar)
  local contours = Polar.collect_contours(polar)
  for _, heatmap in ipairs(heatmaps) do
    if heatmap.rmax > observed then observed = heatmap.rmax end
  end
  for _, contour in ipairs(contours) do
    if contour.rmax > observed then observed = contour.rmax end
  end
  rmax = rmax or (observed > 0 and observed or 1)
  return {
    polar = polar,
    series = collected,
    heatmaps = heatmaps,
    contours = contours,
    colorbar = Polar.collect_colorbar(polar, heatmaps),
    observed = observed,
    rmax = rmax,
    theta_zero = theta_zero,
    direction = direction,
  }
end

-- Ring ticks are filtered to positive values inside rmax.  Scenes without
-- r_ticks get four evenly spaced rings.
function Polar.rings(polar, rmax)
  local rings = {}
  if type(polar) == "table" and type(polar.r_ticks) == "table" then
    for _, tick in ipairs(polar.r_ticks) do
      if type(tick) == "table" and finite_number(tick.value) and
         tick.value > 0 and tick.value <= rmax * (1 + 1e-9) then
        rings[#rings + 1] = tick
      end
    end
  end
  if #rings == 0 then
    for index = 1, 4 do
      rings[#rings + 1] = { value = rmax * index / 4 }
    end
  end
  return rings
end

-- Spoke ticks accept any finite theta.  Scenes without theta_ticks get the
-- usual twelve-spoke fallback.
function Polar.spokes(polar)
  local spokes = {}
  if type(polar) == "table" and type(polar.theta_ticks) == "table" then
    for _, tick in ipairs(polar.theta_ticks) do
      if type(tick) == "table" and finite_number(tick.value) then
        spokes[#spokes + 1] = tick
      end
    end
  end
  if #spokes == 0 then
    for index = 0, 11 do
      spokes[#spokes + 1] = { value = index * pi / 6 }
    end
  end
  return spokes
end

local function fallback_number(value, suffix)
  if not finite_number(value) then return nil end
  return string.format("%.4g", value) .. (suffix or "")
end

-- Explicit labels are used when short enough; long labels are omitted rather
-- than clipped (the export guarantees this and the live renderer matches).
-- Missing labels fall back to a compact numeric value.
function Polar.radius_label(tick)
  if type(tick) ~= "table" then return nil end
  if type(tick.label) == "string" then
    if tick.label == "" then return fallback_number(tick.value) end
    if #tick.label <= Polar.RADIUS_LABEL_LIMIT then return tick.label end
    return nil
  end
  return fallback_number(tick.value)
end

function Polar.theta_label(tick)
  if type(tick) ~= "table" then return nil end
  if type(tick.label) == "string" then
    if tick.label == "" then
      return fallback_number(tick.value * 180 / pi, "°")
    end
    if #tick.label <= Polar.THETA_LABEL_LIMIT then return tick.label end
    return nil
  end
  return fallback_number(tick.value * 180 / pi, "°")
end

-- Samples are capped so a huge kernel series never stalls a frame or bloats
-- the exported SVG.  The stride is shared by both renderers.
function Polar.sample_step(count, limit)
  if type(count) ~= "number" or count <= 0 then return 1 end
  limit = limit or Polar.LINE_SAMPLE_LIMIT
  return math.max(1, math.ceil(count / limit))
end

-- Largest circle that fits the plot box, with the historical 10px breathing
-- room used by the SVG preview.
function Polar.frame_radius(plot_w, plot_h)
  return math.max(1, math.min(plot_w, plot_h) / 2 - 10)
end

-- Project polar data into y-down screen coordinates.  Radii outside rmax clamp
-- to the frame instead of overflowing the viewport.
function Polar.project(cx, cy, radius, rmax, theta_zero, direction, theta, value)
  local angle = theta_zero + direction * theta
  local ratio = value / rmax
  if ratio > 1 then ratio = 1 elseif ratio < -1 then ratio = -1 end
  return cx + radius * ratio * math.cos(angle),
    cy - radius * ratio * math.sin(angle), angle
end

function Polar.ring_label_position(cx, cy, ring_radius)
  return cx + ring_radius - 3, cy + 3
end

function Polar.theta_label_position(cx, cy, radius, angle)
  local label_radius = radius + Polar.THETA_LABEL_GAP
  return cx + label_radius * math.cos(angle),
    cy - label_radius * math.sin(angle) + 3
end

-- Clamp a per-point scatter radius exactly like the SVG preview.
function Polar.point_radius(point)
  local value = type(point) == "table" and point.radius or nil
  if not finite_number(value) then value = Polar.DEFAULT_POINT_RADIUS end
  return math.max(Polar.MIN_POINT_RADIUS,
    math.min(Polar.MAX_POINT_RADIUS, value))
end

-- Split a polar bar into convex filled sectors.  A bar wider than a half turn
-- is rendered as multiple sectors; a full turn becomes a filled circle.  The
-- returned start/end angles are already in screen/world angle space (they
-- include theta_zero and theta_direction), which lets the SVG arc and the live
-- polygon share exactly the same geometry.
function Polar.bar_sectors(bar, frame_radius, rmax, theta_zero, direction)
  if type(bar) ~= "table" then return {} end
  local value = bar.r
  if not finite_number(value) or not finite_number(bar.theta) then return {} end
  local ratio = math.abs(value) / rmax
  if ratio > 1 then ratio = 1 end
  if ratio <= 0 then return {} end
  local width = finite_number(bar.width) and bar.width or
    Polar.DEFAULT_BAR_WIDTH
  local half = math.min(pi, math.abs(width) / 2)
  local span = half * 2
  if span <= 1e-12 then return {} end
  local theta = bar.theta + (value < 0 and pi or 0)
  local bar_radius = frame_radius * ratio
  if span >= 2 * pi - 1e-9 then
    return { {
      full = true, radius = bar_radius, ratio = ratio, color = bar.color,
    } }
  end
  local count = math.max(1, math.ceil(span / pi))
  local step = span / count
  local sectors = {}
  for index = 1, count do
    local start_angle = theta - half + (index - 1) * step
    local end_angle = start_angle + step
    sectors[index] = {
      radius = bar_radius,
      ratio = ratio,
      color = bar.color,
      start_angle = theta_zero + direction * start_angle,
      end_angle = theta_zero + direction * end_angle,
    }
  end
  return sectors
end

-- Flat x/y/z vertex list for LÖVR's Pass:polygon: the center followed by the
-- arc.  The renderer passes this table directly to the host.
function Polar.sector_points(cx, cy, sector)
  local points = { cx, cy, 0 }
  local start_angle, end_angle = sector.start_angle, sector.end_angle
  local span = math.abs(end_angle - start_angle)
  local steps = math.max(2, math.ceil(span / (pi / 24)))
  for index = 0, steps do
    local angle = start_angle +
      (end_angle - start_angle) * index / steps
    points[#points + 1] = cx + sector.radius * math.cos(angle)
    points[#points + 1] = cy - sector.radius * math.sin(angle)
    points[#points + 1] = 0
  end
  return points
end

-- SVG arc flags derived from the same sector angles.  In SVG's y-down space,
-- increasing `angle` moves counterclockwise visually, so sweep is 0.
function Polar.arc_flags(sector)
  local span = math.abs(sector.end_angle - sector.start_angle)
  local large = span > pi and 1 or 0
  local sweep = sector.end_angle < sector.start_angle and 1 or 0
  return large, sweep
end

-- ---------------------------------------------------------------------------
-- Polar fields: heatmaps, contours, and the colourbar.  These helpers are the
-- single source of truth for the live viewport, the static export, and the
-- browser front-end.  See webapp/js/polar.js for the JavaScript counterpart.

Polar.COLORBAR_WIDTH = 16
Polar.COLORBAR_GAP = 16
Polar.COLORBAR_MARGIN = 56
Polar.COLORBAR_STEPS = 40
Polar.FULL_TURN_PARTS = 48
Polar.CONTOUR_MAX_STEPS = 64
Polar.CONTOUR_LABEL_SCALE = 5.5

-- A large field is painted as at most this many block cells.  The live
-- viewport, the SVG export, and the browser renderer all use the same
-- sampling, so even a 512x512 field paints a bounded number of cells and
-- produces a bounded export.
Polar.HEATMAP_CELL_LIMIT = 4096

-- Viridis-like anchors copied from luaplotlib's colour helper.  The channel
-- rounding must stay identical in Lua and JavaScript or the exported SVG, the
-- live frame, and the browser Canvas would select different fills.
Polar.HEAT_ANCHORS = {
  { 0.267, 0.005, 0.329 },
  { 0.188, 0.407, 0.554 },
  { 0.128, 0.567, 0.551 },
  { 0.369, 0.789, 0.383 },
  { 0.993, 0.906, 0.144 },
}

local function clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function finite_integer(value, minimum)
  if not finite_number(value) or value < minimum then return nil end
  if math.floor(value) ~= value then return nil end
  return value
end

local function clamp01(value)
  if not finite_number(value) then return 1 end
  return clamp(value, 0, 1)
end

-- Map a field value to the compact viridis-like palette.  Values outside
-- [vmin, vmax] clamp exactly like luaplotlib's renderer.
function Polar.heat_color(value, vmin, vmax)
  if not finite_number(value) then value = vmin end
  if not finite_number(vmin) or not finite_number(vmax) or vmax <= vmin then
    return "#440154"
  end
  local t = clamp((value - vmin) / (vmax - vmin), 0, 1)
  local scaled = t * (#Polar.HEAT_ANCHORS - 1)
  local index = math.floor(scaled) + 1
  if index >= #Polar.HEAT_ANCHORS then
    index = #Polar.HEAT_ANCHORS - 1
  end
  local fraction = scaled - (index - 1)
  local a = Polar.HEAT_ANCHORS[index]
  local b = Polar.HEAT_ANCHORS[index + 1]
  local function channel(left, right)
    return math.floor((left + (right - left) * fraction) * 255 + 0.5)
  end
  return string.format("#%02x%02x%02x", channel(a[1], b[1]),
    channel(a[2], b[2]), channel(a[3], b[3]))
end

-- Compact colourbar labels.  The result is deterministic in Lua and JS:
-- three significant digits in plain notation for everyday ranges, and a
-- short exponent form outside it.  The suffix of `tostring` is stable on
-- LuaJIT and PUC Lua 5.1 for the ranges used by scene IR.
function Polar.compact_number(value)
  if not finite_number(value) then return nil end
  if value == 0 then return "0" end
  local magnitude = math.abs(value)
  if magnitude >= 1e-4 and magnitude < 1e5 then
    local rounded = tonumber(string.format("%.3g", value))
    if rounded == nil then return string.format("%.3g", value) end
    return tostring(rounded)
  end
  local text = string.format("%.2e", value)
  local mantissa, exponent = text:match("^(.-)e([+-]?%d+)$")
  if mantissa == nil then return text end
  return tostring(tonumber(mantissa)) .. "e" .. tostring(tonumber(exponent))
end

-- Choose the row/column strides used to paint a heatmap.  A field at or below
-- `limit` keeps every cell.  Larger fields are sampled so that the number of
-- painted block cells stays at or below the limit; each painted block covers
-- the source cells it replaces, so downsampling never leaves gaps in the
-- annulus.  The stride is deterministic and shared by all three renderers.
function Polar.heatmap_sampling(rows, cols, limit)
  limit = finite_integer(limit, 1) or Polar.HEATMAP_CELL_LIMIT
  rows = finite_integer(rows, 1) or 1
  cols = finite_integer(cols, 1) or 1
  if rows <= limit and cols <= math.floor(limit / rows) then
    return {
      row_step = 1, col_step = 1,
      sampled_rows = rows, sampled_cols = cols,
      count = rows * cols, sampled = false,
    }
  end
  -- Start from proportional targets, then fill the cell budget while keeping
  -- the block count under the limit.
  local target = limit * rows / cols
  if target > limit then target = limit end
  if target < 1 then target = 1 end
  local row_target = math.floor(math.sqrt(target))
  if row_target < 1 then row_target = 1 end
  if row_target > rows then row_target = rows end
  local col_target = math.floor(limit / row_target)
  if col_target > cols then col_target = cols end
  if col_target < 1 then col_target = 1 end
  local row_step = math.ceil(rows / row_target)
  local col_step = math.ceil(cols / col_target)
  for _ = 1, 3 do
    local sampled_rows = math.ceil(rows / row_step)
    local max_cols = math.floor(limit / sampled_rows)
    if max_cols < 1 then max_cols = 1 end
    local next_cols = math.min(cols, max_cols)
    col_step = math.ceil(cols / next_cols)
    local sampled_cols = math.ceil(cols / col_step)
    local max_rows = math.floor(limit / sampled_cols)
    if max_rows < 1 then max_rows = 1 end
    local next_rows = math.min(rows, max_rows)
    row_step = math.ceil(rows / next_rows)
  end
  local sampled_rows = math.ceil(rows / row_step)
  local sampled_cols = math.ceil(cols / col_step)
  return {
    row_step = row_step,
    col_step = col_step,
    sampled_rows = sampled_rows,
    sampled_cols = sampled_cols,
    count = sampled_rows * sampled_cols,
    sampled = true,
  }
end

-- Copy one heatmap from the polar IR into the compact field shape used by the
-- renderers.  Missing or non-finite metadata gets the same safe defaults as
-- the rest of the module; non-finite matrix cells fall back to `vmin`.
--
-- When a field exceeds `Polar.HEATMAP_CELL_LIMIT` only the sampled block
-- values are copied.  `vmin`/`vmax` still describe the full matrix: an
-- explicit range is used as-is, otherwise every source cell is scanned once.
function Polar.collect_heatmaps(polar)
  local heatmaps = {}
  for _, item in ipairs(type(polar) == "table" and polar.heatmaps or {}) do
    if type(item) == "table" then
      local rows = finite_integer(item.rows, 1)
      local cols = finite_integer(item.cols, 1)
      local values = type(item.values) == "table" and item.values or nil
      if rows and cols and values then
        local sampling = Polar.heatmap_sampling(rows, cols)
        local has_vmin = finite_number(item.vmin)
        local has_vmax = finite_number(item.vmax)
        local minimum, maximum
        if not (has_vmin and has_vmax) then
          for row = 1, rows do
            local source = type(values[row]) == "table" and values[row] or {}
            for col = 1, cols do
              local value = source[col]
              if finite_number(value) then
                if minimum == nil or value < minimum then minimum = value end
                if maximum == nil or value > maximum then maximum = value end
              end
            end
          end
        end
        local cells = {}
        if sampling.sampled then
          for sample_row = 1, sampling.sampled_rows do
            local source_row = 1 + (sample_row - 1) * sampling.row_step +
              math.floor((sampling.row_step - 1) / 2)
            if source_row > rows then source_row = rows end
            local source = type(values[source_row]) == "table" and
              values[source_row] or {}
            local copied = {}
            for sample_col = 1, sampling.sampled_cols do
              local source_col = 1 + (sample_col - 1) * sampling.col_step +
                math.floor((sampling.col_step - 1) / 2)
              if source_col > cols then source_col = cols end
              local value = source[source_col]
              if finite_number(value) then copied[sample_col] = value end
            end
            cells[sample_row] = copied
          end
        else
          for row = 1, rows do
            local source = type(values[row]) == "table" and values[row] or {}
            local copied = {}
            for col = 1, cols do
              local value = source[col]
              if finite_number(value) then copied[col] = value end
            end
            cells[row] = copied
          end
        end
        local vmin = has_vmin and item.vmin or minimum
        local vmax = has_vmax and item.vmax or maximum
        if vmin == nil then vmin = 0 end
        if vmax == nil or vmax <= vmin then vmax = vmin + 1 end
        local rmin = finite_number(item.rmin) and math.max(0, item.rmin) or 0
        local rmax = finite_number(item.rmax) and item.rmax or rows
        if rmax <= rmin then rmax = rmin + 1 end
        local theta_min = finite_number(item.theta_min) and item.theta_min or 0
        local theta_max = finite_number(item.theta_max) and item.theta_max or
          theta_min + 2 * pi
        if theta_max <= theta_min then theta_max = theta_min + 2 * pi end
        if theta_max - theta_min > 2 * pi then theta_max = theta_min + 2 * pi end
        heatmaps[#heatmaps + 1] = {
          kind = "heatmap",
          rows = rows,
          cols = cols,
          values = cells,
          vmin = vmin,
          vmax = vmax,
          rmin = rmin,
          rmax = rmax,
          theta_min = theta_min,
          theta_max = theta_max,
          alpha = clamp01(item.alpha),
          label = type(item.label) == "string" and item.label or nil,
          colorbar = item.colorbar == true,
          row_step = sampling.row_step,
          col_step = sampling.col_step,
          sampled = sampling.sampled,
          sampled_cells = sampling.count,
        }
      end
    end
  end
  return heatmaps
end

-- Copy contour levels from the polar IR.  The exported segments are already
-- data-space (theta, r) quadruples, so all three renderers only need the
-- shared projection and subdivision helpers.
function Polar.collect_contours(polar)
  local contours = {}
  for index, item in ipairs(type(polar) == "table" and polar.contours or {}) do
    if type(item) == "table" and type(item.levels) == "table" then
      local style = type(item.style) == "table" and item.style or {}
      local rmin = finite_number(item.rmin) and math.max(0, item.rmin) or 0
      local rmax = finite_number(item.rmax) and item.rmax or rmin + 1
      if rmax <= rmin then rmax = rmin + 1 end
      local theta_min = finite_number(item.theta_min) and item.theta_min or 0
      local theta_max = finite_number(item.theta_max) and item.theta_max or
        theta_min + 2 * pi
      if theta_max <= theta_min then theta_max = theta_min + 2 * pi end
      if theta_max - theta_min > 2 * pi then
        theta_max = theta_min + 2 * pi
      end
      local levels = {}
      for _, level in ipairs(item.levels) do
        if type(level) == "table" and finite_number(level.level) and
           type(level.segments) == "table" then
          local segments = {}
          for _, segment in ipairs(level.segments) do
            if type(segment) == "table" and finite_number(segment[1]) and
               finite_number(segment[2]) and finite_number(segment[3]) and
               finite_number(segment[4]) then
              segments[#segments + 1] = {
                segment[1], segment[2], segment[3], segment[4],
              }
            end
          end
          if #segments > 0 then
            levels[#levels + 1] = { level = level.level, segments = segments }
          end
        end
      end
      if #levels > 0 then
        local linestyle = style.linestyle
        if linestyle ~= "dashed" and linestyle ~= "dotted" and
           linestyle ~= "none" then
          linestyle = "solid"
        end
        local color = valid_color(style.color)
        if color == nil then
          color = Polar.PALETTE[(index - 1) % #Polar.PALETTE + 1]
        end
        contours[#contours + 1] = {
          kind = "contour",
          rows = finite_integer(item.rows, 1),
          cols = finite_integer(item.cols, 1),
          rmin = rmin,
          rmax = rmax,
          theta_min = theta_min,
          theta_max = theta_max,
          levels = levels,
          labels = item.labels == true,
          style = {
            color = color,
            linewidth = finite_number(style.linewidth) and
              math.max(0, style.linewidth) or 1.5,
            alpha = clamp01(style.alpha),
            linestyle = linestyle,
            label = type(style.label) == "string" and style.label or nil,
          },
        }
      end
    end
  end
  return contours
end

-- Resolve the vertical colourbar metadata.  A scene normally supplies
-- `polar.colorbar`; if only the heatmap carries `colorbar = true`, derive the
-- same three-tick bar from the first such heatmap.
function Polar.collect_colorbar(polar, heatmaps)
  local item = type(polar) == "table" and type(polar.colorbar) == "table" and
    polar.colorbar or nil
  local source
  if item ~= nil then
    source = item
  else
    for _, heatmap in ipairs(heatmaps or {}) do
      if heatmap.colorbar then source = heatmap break end
    end
  end
  if source == nil then return nil end
  local vmin = finite_number(source.vmin) and source.vmin or nil
  local vmax = finite_number(source.vmax) and source.vmax or nil
  if vmin == nil or vmax == nil or vmax <= vmin then return nil end
  local ticks = {}
  if type(source.ticks) == "table" and #source.ticks >= 2 then
    for _, value in ipairs(source.ticks) do
      if finite_number(value) then ticks[#ticks + 1] = value end
    end
  end
  if #ticks < 2 then
    ticks = {}
    for index = 1, 3 do
      ticks[index] = vmin + (vmax - vmin) * (index - 1) / 2
    end
  end
  return {
    orientation = source.orientation == "horizontal" and "horizontal" or
      "vertical",
    vmin = vmin,
    vmax = vmax,
    ticks = ticks,
    label = type(source.label) == "string" and source.label ~= "" and
      source.label or nil,
  }
end

-- Reserve a column for the colourbar before fitting the circle.  Without a
-- bar this is exactly `frame_radius(plot_w, plot_h)` and the historical
-- centre, so existing scenes keep their pixels.
function Polar.frame_layout(left, top, right, bottom, has_colorbar)
  local plot_w = math.max(1, right - left)
  local plot_h = math.max(1, bottom - top)
  local field_w = math.max(1, plot_w -
    (has_colorbar and Polar.COLORBAR_MARGIN or 0))
  return left + field_w / 2, top + plot_h / 2,
    Polar.frame_radius(field_w, plot_h)
end

function Polar.colorbar_layout(cx, cy, radius)
  local width = Polar.COLORBAR_WIDTH
  local height = radius * 1.7
  return cx + radius + Polar.COLORBAR_GAP, cy - height / 2, width, height
end

function Polar.colorbar_ticks(colorbar)
  local ticks = {}
  if type(colorbar) ~= "table" then return ticks end
  local span = colorbar.vmax - colorbar.vmin
  if span <= 0 then return ticks end
  for _, value in ipairs(colorbar.ticks or {}) do
    if finite_number(value) then
      local fraction = clamp((value - colorbar.vmin) / span, 0, 1)
      ticks[#ticks + 1] = {
        value = value,
        label = Polar.compact_number(value),
        fraction = fraction,
      }
    end
  end
  return ticks
end

-- Return the evenly stepped colourbar fills (first step at the top, matching
-- luaplotlib's vertical bar).
function Polar.colorbar_steps(colorbar, count)
  local steps = {}
  if type(colorbar) ~= "table" then return steps end
  count = count or Polar.COLORBAR_STEPS
  local span = colorbar.vmax - colorbar.vmin
  if span <= 0 or count <= 0 then return steps end
  for index = 1, count do
    local value = colorbar.vmax - span * ((index - 0.5) / count)
    steps[#steps + 1] = {
      value = value,
      color = Polar.heat_color(value, colorbar.vmin, colorbar.vmax),
      y0 = (index - 1) / count,
      y1 = index / count,
    }
  end
  return steps
end

-- Project every painted matrix block into an annular sector (or a full disc /
-- split ring) in y-down screen coordinates.  A full turn with an inner radius
-- is split into convex wedges so the LÖVR polygon path never needs a hole.
-- Large fields are sampled into blocks by `heatmap_sampling`; each block spans
-- the source rows/columns it replaces so the sampled field still covers the
-- whole annulus.  Cells keep their source row/column indices plus `row_span`
-- and `col_span` for the export and QA.
function Polar.heatmap_cells(heatmap, cx, cy, radius, rmax, theta_zero,
    direction)
  local cells = {}
  if type(heatmap) ~= "table" then return cells end
  rmax = finite_number(rmax) and rmax > 0 and rmax or 1
  local sampling = Polar.heatmap_sampling(heatmap.rows, heatmap.cols)
  local row_step = finite_integer(heatmap.row_step, 1) or sampling.row_step
  local col_step = finite_integer(heatmap.col_step, 1) or sampling.col_step
  row_step = math.max(1, math.min(row_step, heatmap.rows))
  col_step = math.max(1, math.min(col_step, heatmap.cols))
  local sampled_values = heatmap.sampled == true
  local outer = radius * math.min(heatmap.rmax, rmax) / rmax
  local inner = radius * math.max(0, heatmap.rmin) / rmax
  if inner > outer then inner = outer end
  local span = heatmap.theta_max - heatmap.theta_min
  local col_span = span / heatmap.cols
  local row_index = 0
  for row = 1, heatmap.rows, row_step do
    row_index = row_index + 1
    local row_end = math.min(heatmap.rows, row + row_step - 1)
    local row_inner = inner + (outer - inner) * (row - 1) / heatmap.rows
    local row_outer = inner + (outer - inner) * row_end / heatmap.rows
    local col_index = 0
    for col = 1, heatmap.cols, col_step do
      col_index = col_index + 1
      local col_end = math.min(heatmap.cols, col + col_step - 1)
      local value
      if sampled_values then
        value = heatmap.values[row_index] and
          heatmap.values[row_index][col_index]
      else
        local sample_row = math.min(row_end,
          row + math.floor((row_step - 1) / 2))
        local sample_col = math.min(col_end,
          col + math.floor((col_step - 1) / 2))
        value = heatmap.values[sample_row] and
          heatmap.values[sample_row][sample_col]
      end
      if not finite_number(value) then value = heatmap.vmin end
      local theta0 = heatmap.theta_min + col_span * (col - 1)
      local theta1 = heatmap.theta_min + col_span * col_end
      local start_angle = theta_zero + direction * theta0
      local end_angle = theta_zero + direction * theta1
      local cell = {
        row = row,
        col = col,
        row_span = row_end - row + 1,
        col_span = col_end - col + 1,
        value = value,
        color = Polar.heat_color(value, heatmap.vmin, heatmap.vmax),
        alpha = heatmap.alpha,
        inner_radius = row_inner,
        outer_radius = row_outer,
        start_angle = start_angle,
        end_angle = end_angle,
      }
      local cell_span = math.abs(end_angle - start_angle)
      if cell_span >= 2 * pi - 1e-9 then
        if row_inner <= 0.0005 then
          cell.full_disc = true
          cell.parts = {}
        else
          cell.parts = {}
          local step = (end_angle - start_angle) / Polar.FULL_TURN_PARTS
          for part = 1, Polar.FULL_TURN_PARTS do
            local part_start = start_angle + step * (part - 1)
            cell.parts[part] = {
              start_angle = part_start,
              end_angle = part_start + step,
            }
          end
        end
      else
        cell.parts = { { start_angle = start_angle, end_angle = end_angle } }
      end
      cells[#cells + 1] = cell
    end
  end
  return cells
end

-- Subdivide one marching-squares contour edge in (theta, r) space so a long
-- contour stays a spiral instead of a coarse chord.  The limits match the
-- luaplotlib renderer.
function Polar.contour_segment_points(contour, segment, cx, cy, radius, rmax,
    theta_zero, direction)
  local points = {}
  if type(segment) ~= "table" or not finite_number(segment[1]) or
     not finite_number(segment[2]) or not finite_number(segment[3]) or
     not finite_number(segment[4]) then
    return points
  end
  rmax = finite_number(rmax) and rmax > 0 and rmax or 1
  local theta0, radius0 = segment[1], segment[2]
  local theta1, radius1 = segment[3], segment[4]
  local angular = math.abs(theta1 - theta0)
  local radial = math.abs(radius1 - radius0) / rmax
  local steps = math.max(2, math.ceil(angular / (pi / 48)),
    math.ceil(radial * radius / 5))
  if steps > Polar.CONTOUR_MAX_STEPS then
    steps = Polar.CONTOUR_MAX_STEPS
  end
  for step = 0, steps do
    local t = step / steps
    local theta = theta0 + (theta1 - theta0) * t
    local value = radius0 + (radius1 - radius0) * t
    local x, y = Polar.project(cx, cy, radius, rmax, theta_zero, direction,
      theta, value)
    points[#points + 1] = { x, y }
  end
  return points
end

-- Place at most one label per contour level on the segment farthest from the
-- origin, clamped inside the circular frame.  All three renderers consume
-- this helper so labels cannot drift between them.
function Polar.contour_label(contour, level, cx, cy, radius, rmax, theta_zero,
    direction)
  if type(contour) ~= "table" or contour.labels ~= true then return nil end
  if type(level) ~= "table" or not finite_number(level.level) or
     type(level.segments) ~= "table" then
    return nil
  end
  local best, best_radius
  for _, segment in ipairs(level.segments) do
    if type(segment) == "table" then
      local mid_theta = (segment[1] + segment[3]) / 2
      local mid_radius = (segment[2] + segment[4]) / 2
      local magnitude = math.abs(mid_radius)
      if best_radius == nil or magnitude > best_radius then
        best = { mid_theta, mid_radius }
        best_radius = magnitude
      end
    end
  end
  if best == nil then return nil end
  local text = Polar.compact_number(level.level)
  if text == nil then return nil end
  local x, y = Polar.project(cx, cy, radius, rmax, theta_zero, direction,
    best[1], best[2])
  local dx, dy = x - cx, y - cy
  local distance = math.sqrt(dx * dx + dy * dy)
  local margin = #text * Polar.CONTOUR_LABEL_SCALE / 2 + 4
  local limit = radius - margin
  if limit > 0 and distance > limit then
    x = cx + dx / distance * limit
    y = cy + dy / distance * limit
  end
  return { x = x, y = y, text = text }
end

return Polar
