--
-- UI theme mapping.  The notebook is authored in a dark palette; light mode
-- inverts HSL lightness while preserving hue, so syntax colors stay meaningful.
--
local Theme = {}
Theme.mode = "dark"
Theme.opacity = 1.0
local cache = {}

local function rgb_to_hsl(r, g, b)
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local l = (max + min) / 2
  if max == min then return 0, 0, l end
  local d = max - min
  local s = l > 0.5 and d / (2 - max - min) or d / (max + min)
  local h
  if max == r then h = (g - b) / d + (g < b and 6 or 0)
  elseif max == g then h = (b - r) / d + 2
  else h = (r - g) / d + 4 end
  return h / 6, s, l
end

local function hue(p, q, t)
  if t < 0 then t = t + 1 end
  if t > 1 then t = t - 1 end
  if t < 1 / 6 then return p + (q - p) * 6 * t end
  if t < 1 / 2 then return q end
  if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
  return p
end

local function hsl_to_rgb(h, s, l)
  if s == 0 then return l, l, l end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return hue(p, q, h + 1 / 3), hue(p, q, h), hue(p, q, h - 1 / 3)
end

function Theme.map(color)
  if Theme.mode == "dark" then return color end
  local key = string.format("%.4f,%.4f,%.4f", color[1], color[2], color[3])
  local mapped = cache[key]
  if mapped == nil then
    local h, s, l = rgb_to_hsl(color[1], color[2], color[3])
    local r, g, b = hsl_to_rgb(h, s, 1 - l)
    mapped = { r, g, b, color[4] or 1 }
    cache[key] = mapped
  end
  return mapped
end

function Theme.set(mode)
  Theme.mode = mode == "light" and "light" or "dark"
end

function Theme.toggle()
  Theme.set(Theme.mode == "dark" and "light" or "dark")
  return Theme.mode
end

function Theme.set_opacity(value)
  value = tonumber(value) or 1
  Theme.opacity = math.max(0.55, math.min(1, value))
  return Theme.opacity
end

function Theme.toggle_transparency()
  return Theme.set_opacity(Theme.opacity >= 0.999 and 0.82 or 1)
end

function Theme.load()
  local ok, value = pcall(lovr.filesystem.read, "theme.txt")
  if ok and value then Theme.set(value:gsub("%s+", "")) end
  local opacity_ok, opacity = pcall(lovr.filesystem.read, "opacity.txt")
  if opacity_ok and opacity then Theme.set_opacity(opacity) end
end

function Theme.save()
  pcall(lovr.filesystem.write, "theme.txt", Theme.mode)
  pcall(lovr.filesystem.write, "opacity.txt", string.format("%.3f",
    Theme.opacity))
end

return Theme
