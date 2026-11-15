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
local json = require("notebook.json")

local Extensions = {
  registry = {},
  order = {},
  errors = {},
  disabled = {},
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
  if Extensions.disabled[id] then return nil end
  return Extensions.registry[id]
end

function Extensions.set_enabled(id, enabled)
  if Extensions.registry[id] == nil then return false end
  Extensions.disabled[id] = not enabled
  return true
end

function Extensions.is_enabled(id)
  return Extensions.registry[id] ~= nil and not Extensions.disabled[id]
end

function Extensions.list()
  local result = {}
  for _, id in ipairs(Extensions.order) do
    local descriptor = Extensions.registry[id]
    if descriptor then
      result[#result + 1] = {
        id = id,
        title = descriptor.title or id,
        enabled = not Extensions.disabled[id],
      }
    end
  end
  return result
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

function Extensions.load_preferences()
  local ok, text = pcall(lovr.filesystem.read, "extensions.json")
  if not ok or text == nil then return end
  local ok_decode, data = pcall(json.decode, text)
  if not ok_decode or type(data) ~= "table" then return end
  for id, disabled in pairs(data) do
    if Extensions.registry[id] then
      Extensions.disabled[id] = disabled == true
    end
  end
end

function Extensions.save_preferences()
  local ok, encoded = pcall(json.encode, Extensions.disabled)
  if not ok then return false end
  return pcall(lovr.filesystem.write, "extensions.json", encoded)
end

function Extensions.discover_user()
  local DisplayList = require("extensions.support.display_list")
  local directory = "user-extensions"
  pcall(lovr.filesystem.createDirectory, directory)
  local loaded, errors = {}, {}
  local ok, items = pcall(lovr.filesystem.getDirectoryItems, directory)
  if not ok then return loaded, { tostring(items) } end
  for _, filename in ipairs(items) do
    local name = filename:match("^([a-z][a-z0-9_-]*)%.json$")
    if name then
      local existing = Extensions.registry[name]
      if existing and existing.tier ~= "declarative" then
        errors[#errors + 1] = name .. ": built-in ids are reserved"
      else
        local text = lovr.filesystem.read(directory .. "/" .. filename)
        local decoded, data = pcall(json.decode, text or "")
        if not decoded or type(data) ~= "table" then
          errors[#errors + 1] = name .. ": invalid JSON"
        else
          local descriptor, err = DisplayList.validate(data, filename)
          if descriptor then
            descriptor.id = descriptor.id or name
            if descriptor.id ~= name then
              errors[#errors + 1] = name .. ": id must match filename"
            else
              if Extensions.registry[name] then
                Extensions.registry[name] = descriptor
              else
                register(descriptor)
              end
              loaded[#loaded + 1] = descriptor
            end
          else
            errors[#errors + 1] = name .. ": " .. tostring(err)
          end
        end
      end
    elseif filename:match("^([a-z][a-z0-9_-]*)%.lua$") then
      local sandbox_name = filename:match("^([a-z][a-z0-9_-]*)%.lua$")
      if Extensions.registry[sandbox_name] then
        errors[#errors + 1] = sandbox_name .. ": built-in ids are reserved"
      else
        local Sandbox = require("extensions.support.sandbox")
        local absolute = lovr.filesystem.getSaveDirectory() .. "/" ..
          directory .. "/" .. filename
        local descriptor, err = Sandbox.run(absolute,
          sandbox_name, lovr.filesystem.getSource())
        if descriptor then
          register(descriptor)
          loaded[#loaded + 1] = descriptor
        else
          errors[#errors + 1] = sandbox_name .. ": " .. tostring(err)
        end
      end
    end
  end
  Extensions.user_loaded = loaded
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
