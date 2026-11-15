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

function Format.load(name)
  local path = "notebooks/" .. name
  local text = lovr.filesystem.read(path)
  if text == nil then return nil, "not found: " .. path end
  return Format.decode(text)
end

return Format
