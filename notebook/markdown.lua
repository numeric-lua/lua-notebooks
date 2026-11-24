--
-- Minimal markdown preview transforms for notebook cells.  This is deliberately
-- not a CommonMark parser; it handles the constructs the notebook itself uses.
--
local Markdown = {}

local CALLOUT_TITLES = {
  note = "Note", tip = "Tip", important = "Important",
  warning = "Warning", caution = "Caution",
}

local function table_cells(line)
  if line:find("|", 1, true) == nil then return nil end
  local trimmed = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\\|", "\1")
  if trimmed:sub(1, 1) == "|" then trimmed = trimmed:sub(2) end
  if trimmed:sub(-1) == "|" then trimmed = trimmed:sub(1, -2) end
  local cells = {}
  for cell in (trimmed .. "|"):gmatch("(.-)|") do
    cells[#cells + 1] = cell:gsub("\1", "|"):gsub("^%s+", ""):gsub("%s+$", "")
  end
  return #cells > 0 and cells or nil
end

local function is_table_rule(cells)
  if cells == nil then return false end
  for _, cell in ipairs(cells) do
    if cell:match("^:?%-+:?$") == nil then return false end
  end
  return true
end

-- Collect per-cell footnote definitions and assign numbers in source reference
-- order.  Fenced code and inline code never create or use a footnote.  The
-- preview only needs the definition text and the number map; the export and
-- browser render the actual reference/section markup.
function Markdown.footnote_context(source)
  local context = { definitions = {}, numbers = {}, order = {} }
  local lines = {}
  for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end

  local in_fence = false
  for _, line in ipairs(lines) do
    if line:match("^%s*[`~][`~][`~]+") then
      in_fence = not in_fence
    elseif not in_fence then
      local label, body = line:match("^%s*%[%^([%w%-_]+)%]:%s*(.*)$")
      if label ~= nil then
        if context.definitions[label] == nil then
          context.definitions[label] = body
        end
      end
    end
  end

  in_fence = false
  for _, line in ipairs(lines) do
    if line:match("^%s*[`~][`~][`~]+") then
      in_fence = not in_fence
    elseif not in_fence then
      local definition = line:match("^%s*%[%^([%w%-_]+)%]:")
      if definition == nil then
        local visible = line:gsub("`[^`]*`", "")
        visible = visible:gsub("\\(%[%^[%w%-_]+%])", "\1")
        for label in visible:gmatch("%[%^([%w%-_]+)%]") do
          if context.definitions[label] ~= nil and
             context.numbers[label] == nil then
            local number = #context.order + 1
            context.numbers[label] = number
            context.order[number] = label
          end
        end
      end
    end
  end
  return context
end

function Markdown.preview(line, footnotes)
  local literals = {}
  line = line:gsub("\\([\\`*_~=%[%]()#+%.!|%-%%])", function(char)
    literals[#literals + 1] = char
    return "\2" .. #literals .. "\2"
  end)
  local function restore(value)
    return (value:gsub("\2(%d+)\2", function(index)
      return literals[tonumber(index)] or ""
    end))
  end
  -- Inline code is literal: hide it from the footnote, link, and emphasis
  -- passes, then put it back without the backticks at the end.
  local code_spans = {}
  line = line:gsub("`([^`]*)`", function(code)
    code_spans[#code_spans + 1] = code
    return "\3" .. #code_spans .. "\3"
  end)

  local definition, definition_text =
    line:match("^%s*%[%^([%w%-_]+)%]:%s*(.*)$")
  if definition ~= nil then
    line = "↳ " .. definition_text
  end

  local quote_depth, quote_rest = 0, line
  while true do
    local prefix, rest = quote_rest:match("^(%s*>%s?)(.*)$")
    if prefix == nil then break end
    quote_depth = quote_depth + 1
    quote_rest = rest
  end
  if quote_depth > 0 then
    local kind, rest = quote_rest:match("^%s*%[!(%a+)%]%s*(.*)$")
    local title = kind and CALLOUT_TITLES[kind:lower()]
    if quote_depth == 1 and title ~= nil then
      line = "▌ " .. title:upper() .. (rest ~= "" and ("  " .. rest) or "")
    else
      line = string.rep("│ ", quote_depth) .. quote_rest
    end
  end

  if line:match("^%s*([%*%-_])%s*%1%s*%1[%s%*%-_]*$") then
    return restore("----------")
  end

  local cells = table_cells(line)
  if is_table_rule(cells) then
    return restore(string.rep("─", math.max(4, #cells * 6)))
  elseif cells ~= nil then
    line = "│ " .. table.concat(cells, " │ ") .. " │"
  else
    line = line:gsub("^%s*#+%s*", "")
    local indent = line:match("^(%s*)") or ""
    local depth = 0
    for character in indent:gmatch(".") do
      depth = depth + (character == "\t" and 2 or 1)
    end
    local prefix = string.rep("  ", math.floor(depth / 2))
    line = line:gsub("^%s*", "")
    local checked, task = line:match("^[-*+]%s+%[([ xX])%]%s+(.*)$")
    if checked ~= nil then
      line = prefix .. (checked:lower() == "x" and "[x] " or "[ ] ") .. task
    else
      local bullet = line:match("^[-*+]%s+(.*)$")
      if bullet ~= nil then
        line = prefix .. "• " .. bullet
      else
        line = prefix .. line
      end
    end
  end
  line = line:gsub("%*%*(.-)%*%*", "%1")
  line = line:gsub("__(.-)__", "%1")
  line = line:gsub("~~(.-)~~", "%1")
  line = line:gsub("==(.-)==", "%1")
  line = line:gsub("%*(.-)%*", "%1")
  line = line:gsub("^_([^_]+)_", "%1")
  line = line:gsub("([^%w_])_([^_]+)_", "%1%2")
  line = line:gsub("%[([^%]]+)%]%b()", "%1")
  line = line:gsub("%[%[([^%]]+)%]%]", "%1")
  if footnotes ~= nil then
    line = line:gsub("%[%^([%w%-_]+)%]", function(label)
      local number = footnotes.numbers[label]
      if number ~= nil then return "[" .. number .. "]" end
      return "[^" .. label .. "]"
    end)
  end
  line = line:gsub("\3(%d+)\3", function(index)
    return code_spans[tonumber(index)] or ""
  end)
  return restore(line)
end

return Markdown
