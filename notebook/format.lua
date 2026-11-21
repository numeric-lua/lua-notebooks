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
      id = cell.id,
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
      id = cell.id,
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

function Format.save_path(notebook, path)
  local handle, err = io.open(path, "wb")
  if handle == nil then return nil, "cannot write " .. path .. ": " .. tostring(err) end
  handle:write(Format.encode(notebook))
  handle:close()
  notebook._path = path
  return path
end

function Format.save(notebook)
  local directory = "notebooks"
  lovr.filesystem.createDirectory(directory)
  local path = directory .. "/" .. notebook.name
  lovr.filesystem.write(path, Format.encode(notebook))
  return path, lovr.filesystem.getSaveDirectory() .. "/" .. path
end

local function autosave_name(notebook)
  local name = notebook.name:gsub("%.luanb$", "")
  name = name:gsub("[^%w_.-]", "_")
  return name
end

function Format.autosave_path(notebook)
  return "autosaves/" .. autosave_name(notebook) .. ".luanb"
end

function Format.write_autosave(notebook)
  if not (lovr and lovr.filesystem) then return nil, "filesystem unavailable" end
  lovr.filesystem.createDirectory("autosaves")
  local path = Format.autosave_path(notebook)
  lovr.filesystem.write(path, Format.encode(notebook))
  return path
end

function Format.load_autosave(notebook)
  if not (lovr and lovr.filesystem) then return nil, "filesystem unavailable" end
  local text = lovr.filesystem.read(Format.autosave_path(notebook))
  if text == nil then return nil, "no autosave" end
  local ok, decoded = pcall(Format.decode, text)
  if not ok then return nil, tostring(decoded) end
  return decoded
end

function Format.remove_autosave(notebook)
  if not (lovr and lovr.filesystem) then return end
  pcall(lovr.filesystem.remove, Format.autosave_path(notebook))
end

function Format.tags(cells)
  local counts, order = {}, {}
  for _, cell in ipairs(cells or {}) do
    if cell.kind == "markdown" then
      for tag in (cell.source or ""):gmatch("#([%a_][%w_-]*)") do
        if counts[tag] == nil then order[#order + 1] = tag end
        counts[tag] = (counts[tag] or 0) + 1
      end
    end
  end
  return counts, order
end

function Format.to_markdown(notebook)
  local lines = { "# " .. notebook:title(), "" }
  for _, cell in ipairs(notebook.cells) do
    if cell.kind == "markdown" then
      lines[#lines + 1] = cell.source or ""
      lines[#lines + 1] = ""
    else
      lines[#lines + 1] = "```lua"
      lines[#lines + 1] = cell.source or ""
      lines[#lines + 1] = "```"
      if cell.scene then
        lines[#lines + 1] = "> scene: " ..
          (type(cell.scene) == "table" and (cell.scene.type or "luaplotlib") or
            tostring(cell.scene))
      end
      if cell.error then
        lines[#lines + 1] = "> error: " .. tostring(cell.error)
      elseif cell.output and cell.output ~= "" then
        for line in (cell.output .. "\n"):gmatch("(.-)\n") do
          lines[#lines + 1] = "> " .. line
        end
      end
      lines[#lines + 1] = ""
    end
  end
  return table.concat(lines, "\n")
end

local function escape_html(value)
  return tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;")
    :gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function markdown_html(source)
  local out = {}
  for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
    local escaped = escape_html(line)
    local level, heading = escaped:match("^(#+)%s+(.*)$")
    if level and #level <= 6 then
      out[#out + 1] = "<h" .. #level .. ">" .. heading .. "</h" .. #level .. ">"
    elseif escaped:match("^%s*[-*+]%s+") then
      local item = escaped:gsub("^%s*[-*+]%s+", "")
      out[#out + 1] = "<ul><li>" .. item .. "</li></ul>"
    elseif escaped ~= "" then
      escaped = escaped:gsub("%*%*(.-)%*%*", "<strong>%1</strong>")
      escaped = escaped:gsub("`([^`]*)`", "<code>%1</code>")
      escaped = escaped:gsub("%[%[([^%]]+)%]%]", "%1")
      out[#out + 1] = "<p>" .. escaped .. "</p>"
    end
  end
  return table.concat(out, "\n")
end

function Format.to_html(notebook)
  local out = { "<!doctype html><html><head><meta charset=\"utf-8\">",
    "<title>" .. escape_html(notebook:title()) ..
    "</title><style>body{font-family:system-ui,sans-serif;max-width:880px;margin:2rem auto;color:#202630}pre{background:#f4f5f7;padding:12px;overflow:auto;border-radius:6px}blockquote{border-left:3px solid #999;padding-left:10px;color:#555}</style></head><body>" }
  for _, cell in ipairs(notebook.cells) do
    if cell.kind == "markdown" then
      out[#out + 1] = markdown_html(cell.source)
    else
      out[#out + 1] = "<pre><code>" .. escape_html(cell.source or "") ..
        "</code></pre>"
      if cell.scene then
        out[#out + 1] = "<blockquote>scene: " .. escape_html(
          type(cell.scene) == "table" and (cell.scene.type or "luaplotlib") or
          tostring(cell.scene)) .. "</blockquote>"
      end
      if cell.error then
        out[#out + 1] = "<blockquote>error: " .. escape_html(cell.error) ..
          "</blockquote>"
      elseif cell.output and cell.output ~= "" then
        out[#out + 1] = "<pre>" .. escape_html(cell.output) .. "</pre>"
      end
    end
  end
  out[#out + 1] = "</body></html>"
  return table.concat(out, "\n")
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
    if lovr.filesystem.isDirectory(path) then
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

function Format.create_folder(name)
  name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-")
  if name == "" or name:find("%.%.") or name:find("/") then
    return nil, "invalid folder name"
  end
  local path = "notebooks/" .. name
  local ok, err = lovr.filesystem.createDirectory(path)
  if not ok then return nil, err end
  return path
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

function Format.delete_path(path)
  local absolute = lovr.filesystem.getSaveDirectory() .. "/" .. path
  local ok, err = os.remove(absolute)
  if not ok then return nil, err end
  return true
end

function Format.delete(name)
  return Format.delete_path("notebooks/" .. name)
end

function Format.load_path(path)
  local text = lovr and lovr.filesystem and lovr.filesystem.read(path)
  if text == nil then
    local handle, err = io.open(path, "rb")
    if handle == nil then return nil, "not found: " .. path .. ": " .. tostring(err) end
    text = handle:read("*a")
    handle:close()
  end
  local ok, notebook = pcall(Format.decode, text)
  if not ok then return nil, tostring(notebook) end
  notebook._path = path
  return notebook
end

function Format.rename_path(old_path, new_name)
  if not new_name:match("%.luanb$") then new_name = new_name .. ".luanb" end
  if new_name:find("%.%.") or new_name:sub(1, 1) == "/" then
    return nil, "invalid notebook name"
  end
  local root = lovr.filesystem.getSaveDirectory() .. "/"
  local target = old_path:match("^(.*)/") or "notebooks"
  local new_path = target .. "/" .. new_name
  local ok, err = os.rename(root .. old_path, root .. new_path)
  if not ok then return nil, err end
  return new_path
end

function Format.load(name)
  local path = "notebooks/" .. name
  local text = lovr.filesystem.read(path)
  if text == nil then return nil, "not found: " .. path end
  return Format.decode(text)
end

return Format
