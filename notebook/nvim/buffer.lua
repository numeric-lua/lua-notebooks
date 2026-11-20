--
-- Notebook <-> Neovim buffer encoding.  Markers are comments so the buffer can
-- retain a Lua filetype while carrying markdown cells too.
--
local Buffer = {}

function Buffer.encode(cells)
  local lines, rows = {}, {}
  for index, cell in ipairs(cells) do
    if cell.kind == "code" or cell.kind == "markdown" then
      lines[#lines + 1] = string.format("-- %%%% cell %d %s", index, cell.kind)
      rows[#rows + 1] = { row = #lines, index = index }
      for source_line in ((cell.source or "") .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = source_line
      end
    end
  end
  return lines, rows
end

function Buffer.decode(lines)
  local sources, order, seen, current, pieces = {}, {}, {}, nil, {}
  local kinds = {}
  local error_message
  local current_kind
  local function flush()
    if current ~= nil then
      if seen[current] then
        error_message = "duplicate cell marker " .. tostring(current)
      end
      seen[current] = true
      kinds[current] = current_kind or "code"
      sources[current] = table.concat(pieces, "\n")
      order[#order + 1] = current
    end
  end
  for _, line in ipairs(lines or {}) do
    local index, kind = line:match("^%-%- %%%% cell (%d+)%s*(%a*)")
    if index then
      flush()
      current = tonumber(index)
      current_kind = kind ~= "" and kind or "code"
      if current_kind ~= "code" and current_kind ~= "markdown" then
        error_message = "unsupported cell kind " .. current_kind
      end
      pieces = {}
    elseif current ~= nil then
      pieces[#pieces + 1] = line
    elseif line:match("%S") then
      error_message = "text before the first cell marker"
    end
  end
  flush()
  return sources, order, error_message, kinds
end

return Buffer
