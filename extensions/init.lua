--
-- Extension registry and discovery.
--
-- A module returns:
--
--   {
--     id = "unique-id",
--     version = 1,
--     title = "Human title",
--     render = function(pass, time, width, height, state) end,
--     pointer = function(state, event) end,  -- optional
--     key = function(state, event) end,      -- optional
--     text = function(state, text) end,      -- optional
--     resize = function(state, width, height) end, -- optional
--   }
--
-- The host owns the Pass/Texture, composition, resizing, and global input.
--
local Extensions = {
  registry = {},
  order = {},
  errors = {},
}

local function register(descriptor)
  local id = descriptor.id
  if Extensions.registry[id] then
    error("duplicate extension id: " .. id, 2)
  end
  Extensions.registry[id] = descriptor
  Extensions.order[#Extensions.order + 1] = id
  return descriptor
end

function Extensions.register(descriptor_or_name, maybe_renderer)
  local descriptor = descriptor_or_name
  if type(descriptor_or_name) == "string" then
    descriptor = maybe_renderer or {}
    descriptor.id = descriptor.id or descriptor_or_name
  end
  return register(descriptor)
end

function Extensions.get(id)
  return Extensions.registry[id]
end

function Extensions.ids()
  local copy = {}
  for index, id in ipairs(Extensions.order) do copy[index] = id end
  return copy
end

function Extensions.reload(id)
  local Loader = require("extensions.loader")
  local descriptor, err = Loader.reload(id)
  if descriptor == nil then return nil, err end
  if descriptor.id ~= id then
    return nil, "reloaded id " .. descriptor.id .. " does not match " .. id
  end
  local previous = Extensions.registry[id]
  Extensions.registry[id] = descriptor
  if previous == nil then
    Extensions.order[#Extensions.order + 1] = id
  end
  return descriptor
end

local function register_or_replace(descriptor)
  if Extensions.registry[descriptor.id] then
    Extensions.registry[descriptor.id] = descriptor
    return descriptor
  end
  return register(descriptor)
end

function Extensions.discover_user()
  local Loader = require("extensions.loader")
  local directory = "user-extensions"
  pcall(lovr.filesystem.createDirectory, directory)
  local loaded, errors = {}, {}
  local ok, items = pcall(lovr.filesystem.getDirectoryItems, directory)
  if not ok then return loaded, { tostring(items) } end
  for _, filename in ipairs(items) do
    local name = filename:match("^([a-z][a-z0-9_-]*)%.lua$")
    if name then
      local descriptor, err = Loader.load_file(directory .. "/" .. filename,
        name)
      if descriptor then
        register_or_replace(descriptor, true)
        loaded[#loaded + 1] = descriptor
      else
        errors[#errors + 1] = name .. ": " .. tostring(err)
      end
    end
  end
  Extensions.user_errors = errors
  return loaded, errors
end

function Extensions.discover()
  local Loader = require("extensions.loader")
  local loaded, errors = Loader.discover({
    register = function(descriptor)
      if Extensions.registry[descriptor.id] then
        return descriptor
      end
      return register(descriptor)
    end,
  })
  Extensions.errors = errors
  return loaded, errors
end

-- Built-ins are available even before filesystem discovery.
register(require("extensions.cube"))

return Extensions
