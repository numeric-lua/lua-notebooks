--
-- Small TeX-subset layout engine: parser + box layout + renderer.
-- Pure Lua for parsing/layout when a measure callback is supplied.
--
local Engine = {}

local SYMBOLS = {
  alpha = "alpha", beta = "beta", gamma = "gamma", delta = "delta",
  theta = "theta", lambda = "lambda", mu = "mu", pi = "pi", sigma = "sigma",
  phi = "phi", omega = "omega", sum = "sum", prod = "prod", int = "int",
  infty = "inf", partial = "partial", nabla = "nabla", pm = "+/-",
  times = "x", cdot = ".", le = "<=", ge = ">=", ne = "!=", to = "->",
  approx = "~=", sqrt = "sqrt",
}

local plain

local function parse_row(text, position, stop)
  local items = {}
  while position <= #text do
    local char = text:sub(position, position)
    if stop and char == stop then break end
    if char == "}" then break end
    if char:match("%s") then
      local spaces = text:match("^%s+", position)
      items[#items + 1] = { kind = "text", text = " " }
      position = position + #spaces
    elseif char == "\\" then
      local name = text:match("^\\([a-zA-Z]+)", position)
      if name == nil then
        items[#items + 1] = { kind = "text", text = char }
        position = position + 1
      else
        position = position + 1 + #name
        if name == "frac" then
          local numerator, next_position = parse_argument(text, position)
          local denominator, final_position = parse_argument(text, next_position)
          items[#items + 1] = { kind = "frac", numerator = numerator,
            denominator = denominator }
          position = final_position
        elseif name == "sqrt" then
          local body, next_position = parse_argument(text, position)
          items[#items + 1] = { kind = "sqrt", body = body }
          position = next_position
        elseif name == "text" then
          local body, next_position = parse_argument(text, position)
          items[#items + 1] = { kind = "text_group", body = body }
          position = next_position
        elseif name == "delimited" then
          local open, first = parse_argument(text, position)
          local body, second = parse_argument(text, first)
          local close, final = parse_argument(text, second)
          items[#items + 1] = { kind = "delimited", open = plain(open),
            body = body, close = plain(close) }
          position = final
        elseif name == "left" or name == "right" then
          local delimiter = text:sub(position, position)
          if delimiter ~= "" and delimiter ~= "." then
            items[#items + 1] = { kind = "text", text = delimiter }
            position = position + 1
          elseif delimiter == "." then
            position = position + 1
          end
        elseif name == "," then
          items[#items + 1] = { kind = "text", text = " " }
        elseif name == ";" or name == ":" then
          items[#items + 1] = { kind = "text", text = "  " }
        elseif name == "quad" then
          items[#items + 1] = { kind = "text", text = "    " }
        elseif name == "qquad" then
          items[#items + 1] = { kind = "text", text = "        " }
        else
          items[#items + 1] = { kind = "text", text = SYMBOLS[name] or name }
        end
      end
    elseif char:match("[%+%-=<>]") then
      items[#items + 1] = { kind = "text", text = " " .. char .. " " }
      position = position + 1
    else
      local start = position
      position = position + 1
      while position <= #text do
        local current = text:sub(position, position)
        if current == "\\" or current == "{" or current == "}" or
           current == "^" or current == "_" or current:match("%s") or
           current:match("[%+%-=<>]") then break end
        position = position + 1
      end
      local atom = { kind = "text", text = text:sub(start, position - 1) }
      local sup, sub
      while position <= #text do
        local marker = text:sub(position, position)
        if marker == "^" or marker == "_" then
          local value, next_position = parse_argument(text, position + 1)
          if marker == "^" then sup = value else sub = value end
          position = next_position
        else break end
      end
      if sup or sub then atom = { kind = "script", base = atom, sup = sup, sub = sub } end
      items[#items + 1] = atom
    end
  end
  return { kind = "row", items = items }, position
end

function parse_argument(text, position)
  while position <= #text and text:sub(position, position):match("%s") do
    position = position + 1
  end
  if text:sub(position, position) == "{" then
    local body, next_position = parse_row(text, position + 1, "}")
    return body, next_position + 1
  end
  local atom, next_position = parse_row(text, position)
  local first = atom.items[1] or { kind = "text", text = "" }
  return first, next_position
end

local ink_cache = {}

local function measure_text(text, style)
  if style.measure then
    local h, d = style.measure.ink(text, style.scale)
    return style.measure.width(text, style.scale), h, d
  end
  local font = style.font
  local width = font:getWidth(text) * style.scale
  local key = tostring(font) .. "\0" .. text
  local cached = ink_cache[key]
  if cached == nil then
    local ok, vertices = pcall(font.getVertices, font, text)
    if ok and type(vertices) == "table" and #vertices > 0 then
      local low, high = 0, 0
      for _, vertex in ipairs(vertices) do
        local y = vertex[2] or 0
        if y < low then low = y end
        if y > high then high = y end
      end
      cached = { high, math.max(0, -low) }
    else
      cached = { font:getAscent(), math.abs(font:getDescent()) }
    end
    ink_cache[key] = cached
  end
  return width, cached[1] * style.scale, cached[2] * style.scale
end

local function empty_box()
  return { w = 0, h = 0, d = 0, ops = {}, items = {} }
end

plain = function(node)
  if node == nil then return "" end
  if node.kind == "text" then return node.text or "" end
  if node.kind == "text_group" then return plain(node.body) end
  if node.kind == "row" then
    local parts = {}
    for _, child in ipairs(node.items or {}) do parts[#parts + 1] = plain(child) end
    return table.concat(parts)
  end
  if node.kind == "script" then return plain(node.base) end
  return ""
end

local function layout(node, style)
  if node == nil then return empty_box() end
  if node.kind == "text" or node.kind == "text_group" then
    local text = node.kind == "text_group" and plain(node.body) or node.text or ""
    local w, h, d = measure_text(text, style)
    return { w = w, h = h, d = d, ops = { { op = "text", text = text,
      x = 0, font = style.font, scale = style.scale } }, items = {} }
  elseif node.kind == "row" then
    local box = empty_box()
    local cursor = 0
    for _, child in ipairs(node.items or {}) do
      local child_box = layout(child, style)
      box.items[#box.items + 1] = { box = child_box, dx = cursor, shift = 0 }
      cursor = cursor + child_box.w
      box.h = math.max(box.h, child_box.h)
      box.d = math.max(box.d, child_box.d)
    end
    box.w = cursor
    return box
  elseif node.kind == "delimited" then
    local body = layout(node.body, style)
    local em = 18 * style.scale
    local factor = math.max(1, math.min(2.5, (body.h + body.d) / em))
    local open_node = { kind = "text", text = node.open or "" }
    local close_node = { kind = "text", text = node.close or "" }
    local open_style = { font = style.font, scale = style.scale * factor,
      display = style.display, measure = style.measure }
    local close_style = open_style
    local open_box = layout(open_node, open_style)
    local close_box = layout(close_node, close_style)
    local box = empty_box()
    box.w = open_box.w + body.w + close_box.w + 4
    box.h = math.max(body.h, open_box.h, close_box.h)
    box.d = math.max(body.d, open_box.d, close_box.d)
    box.items[#box.items + 1] = { box = open_box, dx = 0, shift = 0 }
    box.items[#box.items + 1] = { box = body, dx = open_box.w + 2, shift = 0 }
    box.items[#box.items + 1] = { box = close_box,
      dx = open_box.w + body.w + 4, shift = 0 }
    return box
  elseif node.kind == "frac" then
    local numerator = layout(node.numerator, style)
    local denominator = layout(node.denominator, style)
    local gap = (style.display and 0.18 or 0.12) * 18 * style.scale
    local axis = 0.26 * 18 * style.scale
    local num_shift = axis + gap + numerator.d
    local den_shift = axis - gap - denominator.h
    local box = empty_box()
    box.w = math.max(numerator.w, denominator.w) + 8
    box.h = math.max(num_shift + numerator.h, axis + 1)
    box.d = math.max(-(den_shift - denominator.d), axis + 1)
    box.items[#box.items + 1] = { box = numerator,
      dx = (box.w - numerator.w) / 2, shift = num_shift }
    box.items[#box.items + 1] = { box = denominator,
      dx = (box.w - denominator.w) / 2, shift = den_shift }
    box.ops[#box.ops + 1] = { op = "rule", x = 3, y = axis - 1,
      w = box.w - 6, h = 1.5 }
    return box
  elseif node.kind == "sqrt" then
    local body = layout(node.body, style)
    local gap = 2 * style.scale
    local top = body.h + gap + 1
    local rad_w = 12 * style.scale
    local d = math.max(body.d + 3 * style.scale, 5 * style.scale)
    local box = empty_box()
    box.w = rad_w + body.w + 6
    box.h = top + 1
    box.d = d
    box.items[#box.items + 1] = { box = body, dx = rad_w + 3, shift = 0 }
    box.ops[#box.ops + 1] = { op = "stroke", x1 = 0, y1 = 4 * style.scale,
      x2 = 4 * style.scale, y2 = -d + 2, thickness = 2 }
    box.ops[#box.ops + 1] = { op = "stroke", x1 = 4 * style.scale,
      y1 = -d + 2, x2 = rad_w, y2 = top, thickness = 2 }
    box.ops[#box.ops + 1] = { op = "rule", x = rad_w, y = top,
      w = box.w - rad_w, h = 1.5 }
    return box
  elseif node.kind == "script" then
    local base = layout(node.base, style)
    local script_style = { font = style.font, scale = style.scale * 0.7,
      display = false, measure = style.measure }
    local sup = node.sup and layout(node.sup, script_style) or empty_box()
    local sub = node.sub and layout(node.sub, script_style) or empty_box()
    local sup_shift = math.max(0.45 * 18 * style.scale,
      base.h - sup.d + 0.05 * 18 * style.scale)
    local sub_shift = math.max(0.22 * 18 * style.scale,
      base.d + 0.08 * 18 * style.scale)
    local box = empty_box()
    box.w = base.w + math.max(sup.w, sub.w) + 2
    box.h = math.max(base.h, sup_shift + sup.h)
    box.d = math.max(base.d, sub_shift + sub.d)
    box.items[#box.items + 1] = { box = base, dx = 0, shift = 0 }
    if node.sup then box.items[#box.items + 1] = { box = sup,
      dx = base.w + 2, shift = sup_shift } end
    if node.sub then box.items[#box.items + 1] = { box = sub,
      dx = base.w + 2, shift = -sub_shift } end
    return box
  end
  return empty_box()
end

local function rewrite_delimiters(source)
  local changed = true
  while changed do
    changed = false
    local start_at = source:find("\\left", 1, true)
    if start_at then
      local open_at = start_at + 5
      while source:sub(open_at, open_at):match("%s") do open_at = open_at + 1 end
      local open = source:sub(open_at, open_at)
      local right_at = source:find("\\right", open_at + 1, true)
      if right_at then
        local close_at = right_at + 6
        while source:sub(close_at, close_at):match("%s") do close_at = close_at + 1 end
        local close = source:sub(close_at, close_at)
        local body = source:sub(open_at + 1, right_at - 1)
        local replacement = "\\delimited{" .. open .. "}{" .. body .. "}{" ..
          close .. "}"
        source = source:sub(1, start_at - 1) .. replacement ..
          source:sub(close_at + 1)
        changed = true
      end
    end
  end
  return source
end

function Engine.typeset(source, options)
  options = options or {}
  local rewritten = rewrite_delimiters(source)
  local ok, tree = pcall(parse_row, rewritten, 1)
  if not ok then return nil, tostring(tree) end
  local style = { font = options.font, scale = options.scale or 0.86,
    display = options.display, measure = options.measure }
  local box = layout(tree, style)
  return { tree = tree, box = box, w = box.w, h = box.h + box.d }
end

local function draw(pass, box, x, baseline, color)
  for _, op in ipairs(box.ops or {}) do
    if op.op == "text" then
      pass:setFont(op.font)
      pass:setColor(color[1], color[2], color[3], color[4] or 1)
      pass:text(op.text, x + op.x, baseline - op.font:getAscent() * op.scale,
        0, op.scale, 0, 0, 1, 0, 0, "left", "top")
    elseif op.op == "rule" then
      pass:setColor(color[1], color[2], color[3], color[4] or 1)
      pass:plane(x + op.x + op.w / 2, baseline - op.y - op.h / 2, 0,
        op.w, op.h)
    elseif op.op == "stroke" then
      local dx, dy = op.x2 - op.x1, op.y2 - op.y1
      pass:setColor(color[1], color[2], color[3], color[4] or 1)
      pass:plane(x + (op.x1 + op.x2) / 2, baseline - (op.y1 + op.y2) / 2,
        0, math.sqrt(dx * dx + dy * dy), op.thickness,
        math.atan2(-dy, dx), 0, 0, 1)
    end
  end
  for _, item in ipairs(box.items or {}) do
    draw(pass, item.box, x + item.dx, baseline - item.shift, color)
  end
end

function Engine.draw(pass, box, x, baseline, color)
  draw(pass, box, x, baseline, color or { 0.88, 0.9, 1, 1 })
end

return Engine
