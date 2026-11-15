--
-- Trusted bootstrap for one sandboxed extension evaluation.
-- Args: extension file, project root (mounted /app).
--
local extension_path = assert(arg[1], "extension path")
package.path = "/app/?.lua;/app/?/init.lua;" .. package.path
local json = require("notebook.json")
local real_print, real_write = print, io.write
print = function() end
io.write = function() end
local chunk, load_error = loadfile(extension_path)
if chunk == nil then
  io.stdout:write(json.encode({ ok = false, error = tostring(load_error) }))
  return
end
local ok, result = pcall(chunk)
print, io.write = real_print, real_write
if ok and type(result) == "table" and result.display then
  io.stdout:write(json.encode({ ok = true, descriptor = result }))
elseif ok then
  io.stdout:write(json.encode({ ok = false, error = "extension must return {display=...}" }))
else
  io.stdout:write(json.encode({ ok = false, error = tostring(result) }))
end
