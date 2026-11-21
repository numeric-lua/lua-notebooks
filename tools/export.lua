-- Headless static export from a source checkout.
--
-- Usage:
--   luajit tools/export.lua INPUT.luanb OUTPUT.html [BACKLINK.luanb ...]
--   luajit tools/export.lua INPUT.luanb -            # write HTML to stdout
--
-- The exporter is pure Lua and does not need LÖVR, which makes it usable in
-- screenshot checks and CI. Backlink notebooks are optional.

local script = arg and arg[0] or "tools/export.lua"
local root = script:match("^(.*)[/\\]tools[/\\][^/\\]+$") or "."
if root == "" then root = "." end
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local Format = require("notebook.format")

local input, output = arg[1], arg[2]
if input == nil or output == nil then
  io.stderr:write("usage: luajit tools/export.lua INPUT.luanb OUTPUT.html " ..
    "[BACKLINK.luanb ...]\n")
  os.exit(2)
end

local notebook, err = Format.load_path(input)
if notebook == nil then
  io.stderr:write("export: " .. tostring(err) .. "\n")
  os.exit(1)
end

local notebooks = { notebook }
for index = 3, #arg do
  local other, other_err = Format.load_path(arg[index])
  if other == nil then
    io.stderr:write("export: " .. tostring(other_err) .. "\n")
    os.exit(1)
  end
  notebooks[#notebooks + 1] = other
end

local html = Format.to_html(notebook,
  Format.backlinks(notebooks, notebook:title()))

if output == "-" then
  io.write(html)
else
  local handle, open_err = io.open(output, "wb")
  if handle == nil then
    io.stderr:write("export: cannot write " .. output .. ": " ..
      tostring(open_err) .. "\n")
    os.exit(1)
  end
  handle:write(html)
  handle:close()
  io.write(string.format("exported %s (%d bytes, %d cells)\n", output,
    #html, #notebook.cells))
end
