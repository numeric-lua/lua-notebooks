--
-- Extension manifest validation.  Pure Lua so the contract can be tested
-- without LÖVR or a graphics device.
--
local Manifest = {}

local ALLOWED_PERMISSIONS = {
  graphics = true, timer = true, input = true,
  filesystem = true, network = true,
}

local function check_callback(descriptor, name)
  if descriptor[name] ~= nil and type(descriptor[name]) ~= "function" then
    return false, "extension." .. name .. " must be a function"
  end
  return true
end

function Manifest.validate(descriptor, source)
  source = source or "extension"
  if type(descriptor) ~= "table" then
    return nil, source .. " must return a table"
  end
  if type(descriptor.id) ~= "string" or
     not descriptor.id:match("^[a-z][a-z0-9_-]*$") then
    return nil, source .. ": id must match ^[a-z][a-z0-9_-]*$"
  end
  if type(descriptor.render) ~= "function" then
    return nil, source .. ": render(pass, time, width, height, state) is required"
  end
  for _, name in ipairs({ "pointer", "key", "text", "resize" }) do
    local ok, err = check_callback(descriptor, name)
    if not ok then return nil, source .. ": " .. err end
  end
  local version = descriptor.version
  if version == nil then version = 1 end
  if type(version) ~= "number" or version < 1 or version % 1 ~= 0 then
    return nil, source .. ": version must be a positive integer"
  end
  descriptor.version = version
  descriptor.title = descriptor.title or descriptor.id
  local permissions = descriptor.permissions or {}
  if type(permissions) ~= "table" then
    return nil, source .. ": permissions must be a table"
  end
  local seen = {}
  for index, permission in ipairs(permissions) do
    if type(permission) ~= "string" or not ALLOWED_PERMISSIONS[permission] then
      return nil, source .. ": invalid permission at index " .. index
    end
    if seen[permission] then
      return nil, source .. ": duplicate permission '" .. permission .. "'"
    end
    seen[permission] = true
  end
  descriptor.permissions = permissions
  return descriptor
end

return Manifest
