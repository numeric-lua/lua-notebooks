--
-- Minimal markdown preview transforms for notebook cells.  This is deliberately
-- not a CommonMark parser; it handles the constructs the notebook itself uses.
--
local Markdown = {}

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

function Markdown.preview(line)
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
  line = line:gsub("`([^`]*)`", "%1")
  line = line:gsub("%[([^%]]+)%]%b()", "%1")
  line = line:gsub("%[%[([^%]]+)%]%]", "%1")
  return restore(line)
end

return Markdown
