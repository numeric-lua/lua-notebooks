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
  local sources, current, pieces = {}, nil, {}
  local function flush()
    if current ~= nil then sources[current] = table.concat(pieces, "\n") end
  end
  for _, line in ipairs(lines or {}) do
    local index = line:match("^%-%- %%%% cell (%d+)")
    if index then
      flush()
      current = tonumber(index)
      pieces = {}
    elseif current ~= nil then
      pieces[#pieces + 1] = line
    end
  end
  flush()
  return sources
end

return Buffer
