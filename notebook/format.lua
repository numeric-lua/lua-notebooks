--
-- .luanb persistence.  Pure encode/decode is testable without LÖVR; save/load
-- use the LÖVR filesystem, which confines writes to the app save directory.
--
local json = require("notebook.json")
local Notebook = require("notebook.model")

local Format = {}

function Format.encode(notebook)
  local cells = {}
  for _, cell in ipairs(notebook.cells) do
    cells[#cells + 1] = {
      kind = cell.kind,
      source = cell.source,
      output = cell.output or "",
      scene = cell.scene,
      widgets = cell.widgets or {},
      collapsed = cell.collapsed and true or false,
    }
  end
  return json.encode({
    version = 1,
    name = notebook.name,
    cells = cells,
  })
end

function Format.decode(text)
  local data = json.decode(text)
  if type(data) ~= "table" or data.version ~= 1 then
    error("notebook: unsupported or missing version", 2)
  end
  if type(data.name) ~= "string" or data.name == "" then
    error("notebook: missing name", 2)
  end
  if type(data.cells) ~= "table" or #data.cells == 0 then
    error("notebook: missing cells", 2)
  end
  local cells = {}
  for index, cell in ipairs(data.cells) do
    if type(cell) ~= "table" then
      error("notebook: cell " .. index .. " is not a table", 2)
    end
    if cell.kind ~= "code" and cell.kind ~= "markdown" then
      error("notebook: invalid cell kind at " .. index, 2)
    end
    cells[index] = {
      kind = cell.kind,
      source = type(cell.source) == "string" and cell.source or "",
      output = type(cell.output) == "string" and cell.output or "",
      scene = cell.scene,
      widgets = type(cell.widgets) == "table" and cell.widgets or {},
      collapsed = cell.collapsed == true,
      running = false,
    }
  end
  return Notebook.new({ name = data.name, cells = cells })
end

function Format.save(notebook)
  local directory = "notebooks"
  lovr.filesystem.createDirectory(directory)
  local path = directory .. "/" .. notebook.name
  lovr.filesystem.write(path, Format.encode(notebook))
  return path, lovr.filesystem.getSaveDirectory() .. "/" .. path
end

function Format.list()
  local items = lovr.filesystem.getDirectoryItems("notebooks")
  local names = {}
  for _, item in ipairs(items) do
    if item:match("%.luanb$") then names[#names + 1] = item end
  end
  table.sort(names)
  return names
end

function Format.list_tree(expanded, prefix, depth)
  prefix = prefix or "notebooks"
  depth = depth or 0
  local entries = {}
  local ok, items = pcall(lovr.filesystem.getDirectoryItems, prefix)
  if not ok then return entries end
  table.sort(items)
  for _, item in ipairs(items) do
    local path = prefix .. "/" .. item
    local info = lovr.filesystem.getInfo(path)
    if info and info.type == "directory" then
      entries[#entries + 1] = { path = path, name = item, depth = depth,
        kind = "directory" }
      if expanded[path] then
        for _, child in ipairs(Format.list_tree(expanded, path, depth + 1)) do
          entries[#entries + 1] = child
        end
      end
    elseif item:match("%.luanb$") then
      entries[#entries + 1] = { path = path, name = item, depth = depth,
        kind = "file" }
    end
  end
  return entries
end

function Format.rename(old_name, new_name)
  if not new_name:match("%.luanb$") then new_name = new_name .. ".luanb" end
  if new_name:find("%.%.") or new_name:sub(1, 1) == "/" then
    return nil, "invalid notebook name"
  end
  local root = lovr.filesystem.getSaveDirectory() .. "/notebooks/"
  local ok, err = os.rename(root .. old_name, root .. new_name)
  if not ok then return nil, err end
  return new_name
end

function Format.delete(name)
  local path = "notebooks/" .. name
  local absolute = lovr.filesystem.getSaveDirectory() .. "/" .. path
  local ok, err = os.remove(absolute)
  if not ok then return nil, err end
  return true
end

function Format.load(name)
  local path = "notebooks/" .. name
  local text = lovr.filesystem.read(path)
  if text == nil then return nil, "not found: " .. path end
  return Format.decode(text)
end

return Format
