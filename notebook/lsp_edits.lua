--
-- Validate and apply LSP WorkspaceEdit changes to notebook cells.
--
local LspEdits = {}

local function position_to_offset(text, position)
  local line, offset = 0, 1
  while line < position.line do
    local newline = text:find("\n", offset, true)
    if newline == nil then return nil end
    offset = newline + 1
    line = line + 1
  end
  local offset_in_line = position.character or 0
  local line_end = text:find("\n", offset, true)
  line_end = line_end and line_end - 1 or #text
  if offset + offset_in_line - 1 > line_end then return nil end
  return offset + offset_in_line
end

local function cell_for_uri(notebook, uri)
  local cell_id = uri:match("[?&]cell=([^&]+)")
  if cell_id == nil then return nil end
  for _, cell in ipairs(notebook.cells) do
    if tostring(cell.id) == cell_id then return cell end
  end
  return nil
end

function LspEdits.apply(notebook, changes)
  if type(changes) ~= "table" then return 0, "no changes" end
  local prepared = {}
  for uri, edits in pairs(changes) do
    local cell = cell_for_uri(notebook, uri)
    if cell == nil then return 0, "unknown cell in edit: " .. uri end
    for _, edit in ipairs(edits) do
      local range = edit.range or {}
      local start_at = position_to_offset(cell.source, range.start or {})
      local end_at = position_to_offset(cell.source, range["end"] or {})
      if start_at == nil or end_at == nil or start_at > end_at then
        return 0, "invalid edit range"
      end
      prepared[#prepared + 1] = { cell = cell, start = start_at,
        finish = end_at, text = tostring(edit.newText or "") }
    end
  end
  table.sort(prepared, function(a, b)
    if a.cell ~= b.cell then return tostring(a.cell.id) < tostring(b.cell.id) end
    return a.start > b.start
  end)
  notebook:push_undo()
  local count = 0
  for _, edit in ipairs(prepared) do
    local source = edit.cell.source
    edit.cell.source = source:sub(1, edit.start - 1) .. edit.text ..
      source:sub(edit.finish)
    edit.cell.cursor = edit.start + #edit.text
    count = count + 1
  end
  notebook.dirty = true
  return count
end

return LspEdits
