--
-- Notebook <-> Neovim buffer encoding.  Markers are comments so the buffer can
-- retain a Lua filetype while carrying markdown cells too.
--
local Buffer = {}

local function editable(cell)
  return cell ~= nil and (cell.kind == "code" or cell.kind == "markdown")
end

local function editable_kind(kind)
  return kind == "code" or kind == "markdown"
end

function Buffer.encode(cells)
  local lines, rows = {}, {}
  for index, cell in ipairs(cells) do
    if editable(cell) then
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
      if not editable_kind(current_kind) then
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

-- Human-readable first line for a cell, used by the deletion confirmation so a
-- destructive marker edit names the content it would remove.
function Buffer.preview(cell, limit)
  limit = limit or 64
  local source = type(cell) == "table" and (cell.source or "") or ""
  for line in (source .. "\n"):gmatch("(.-)\n") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then
      if #trimmed > limit then
        return trimmed:sub(1, limit - 1) .. "…"
      end
      return trimmed
    end
  end
  return "(empty cell)"
end

function Buffer.missing_previews(cells, missing, limit)
  local result = {}
  for _, index in ipairs(missing or {}) do
    result[#result + 1] = {
      index = index,
      preview = Buffer.preview(cells and cells[index], limit),
    }
  end
  return result
end

-- Validate a notebook-wide buffer against the live cell list.  The plan keeps
-- the marker-deletion decision separate from applying it: callers must ask the
-- user before passing delete_missing to Buffer.apply.
function Buffer.plan(cells, lines)
  cells = cells or {}
  local sources, order, decode_error, kinds = Buffer.decode(lines)
  if decode_error then return nil, decode_error end
  if #order == 0 then return nil, "buffer has no cell markers" end

  local old_count = #cells
  local all_editable = true
  for _, cell in ipairs(cells) do
    if not editable(cell) then all_editable = false end
  end
  local new_limit = all_editable and old_count + 100 or old_count
  local seen = {}
  for _, index in ipairs(order) do
    if index < 1 or index > new_limit or seen[index] then
      return nil, "bad cell marker " .. tostring(index)
    end
    seen[index] = true
  end

  local missing = {}
  for index, cell in ipairs(cells) do
    if not seen[index] then
      if not editable(cell) then
        return nil, "cell " .. index .. " cannot be represented by a marker"
      end
      missing[#missing + 1] = index
    end
  end

  local changed, added = false, 0
  for index, source in pairs(sources) do
    if index <= old_count then
      local cell = cells[index]
      if cell and cell.source ~= source then changed = true end
    else
      added = added + 1
      local kind = kinds[index] or "code"
      if not editable_kind(kind) then
        return nil, "bad cell kind " .. tostring(kind)
      end
    end
  end

  local reordered = #order ~= old_count
  if not reordered then
    for position, index in ipairs(order) do
      if index ~= position then reordered = true; break end
    end
  end

  return {
    sources = sources,
    order = order,
    kinds = kinds,
    old_count = old_count,
    missing = missing,
    added = added,
    changed = changed,
    reordered = reordered,
    all_editable = all_editable,
  }
end

-- Apply a validated plan.  Missing markers stay fail-closed unless the caller
-- explicitly passes delete_missing after confirmation, which makes the delete
-- intentional and undoable instead of silently dropping a cell.
function Buffer.apply(notebook, plan, options)
  options = options or {}
  if notebook == nil or plan == nil then return nil, "missing notebook plan" end
  if #plan.missing > 0 and not options.delete_missing then
    return nil, "missing marker for cell " .. tostring(plan.missing[1])
  end
  if #plan.missing > 0 and not plan.all_editable then
    return nil, "cannot delete cell " .. tostring(plan.missing[1])
  end
  if #plan.order == 0 then return nil, "buffer has no cell markers" end

  local created = {}
  for _, index in ipairs(plan.order) do
    if index > plan.old_count then
      local kind = plan.kinds[index] or "code"
      if not editable_kind(kind) then
        return nil, "bad cell kind " .. tostring(kind)
      end
      created[index] = notebook:new_cell(kind, plan.sources[index] or "")
    end
  end

  local deleted = #plan.missing
  local mutated = plan.changed or plan.added > 0 or plan.reordered or
    deleted > 0
  if mutated then notebook:push_undo(options.label or "Neovim notebook edit") end

  local active_cell = notebook.cells[notebook.active]
  local previous_active = notebook.active or 1
  for index, source in pairs(plan.sources) do
    if index <= plan.old_count then
      local cell = notebook.cells[index]
      if cell then cell.source = source end
    end
  end

  local rebuilt = {}
  for _, index in ipairs(plan.order) do
    if index <= plan.old_count then
      local cell = notebook.cells[index]
      if cell then rebuilt[#rebuilt + 1] = cell end
    else
      rebuilt[#rebuilt + 1] = created[index]
    end
  end
  if #rebuilt == 0 then return nil, "buffer has no cells" end
  notebook.cells = rebuilt

  local active
  if active_cell then
    for index, cell in ipairs(rebuilt) do
      if cell == active_cell then active = index; break end
    end
  end
  notebook.active = active or math.max(1,
    math.min(previous_active, #rebuilt))
  if mutated then notebook.dirty = true end
  return {
    added = plan.added,
    deleted = deleted,
    changed = mutated,
    reordered = plan.reordered,
  }
end

return Buffer
