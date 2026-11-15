--
-- Discover and load extension modules from a directory.  The loader accepts
-- injectable list/require/register functions so it can be tested without LÖVR.
--
local Manifest = require("extensions.manifest")

local Loader = {}

local INTERNAL = {
  init = true,
  loader = true,
  manifest = true,
}

function Loader.load(name, options)
  options = options or {}
  local require_module = options.require or require
  local ok, descriptor = pcall(require_module, "extensions." .. name)
  if not ok then
    return nil, descriptor
  end
  if descriptor == nil then
    return nil, "module returned nil"
  end
  return Manifest.validate(descriptor, "extensions/" .. name .. ".lua")
end

function Loader.load_file(path, name, options)
  options = options or {}
  local load = options.load or lovr.filesystem.load
  local chunk, load_error = load(path)
  if chunk == nil then return nil, load_error end
  local ok, descriptor = pcall(chunk)
  if not ok then return nil, descriptor end
  if type(descriptor) ~= "table" then
    return nil, path .. " must return a table"
  end
  descriptor.id = descriptor.id or name
  return Manifest.validate(descriptor, path)
end

function Loader.reload(name, options)
  package.loaded["extensions." .. name] = nil
  return Loader.load(name, options)
end

function Loader.discover(options)
  options = options or {}
  local list = options.list or function()
    return lovr.filesystem.getDirectoryItems("extensions")
  end
  local register = options.register
  if type(register) ~= "function" then
    error("loader.discover requires a register callback", 2)
  end
  local loaded, errors = {}, {}
  local files = list()
  for _, filename in ipairs(files) do
    local name = filename:match("^([a-z][a-z0-9_-]*)%.lua$")
    if name and not INTERNAL[name] then
      local descriptor, err = Loader.load(name, options)
      if descriptor then
        local ok, register_error = pcall(register, descriptor)
        if ok then
          loaded[#loaded + 1] = descriptor
        else
          errors[#errors + 1] = name .. ": " .. tostring(register_error)
        end
      else
        errors[#errors + 1] = name .. ": " .. tostring(err)
      end
    end
  end
  return loaded, errors
end

return Loader
