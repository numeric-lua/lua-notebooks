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
  rmax = rmax or (observed > 0 and observed or 1)
  return {
    polar = polar,
    series = collected,
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

return Polar
