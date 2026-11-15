--
-- Extension renderer registry.  An extension is a table with:
--
--   render(pass, time, width, height)
--
-- It receives only a Pass that targets its own Texture; the notebook owns the
-- window, composition, resizing, and event routing.
--
local Extensions = {
  registry = {},
}

function Extensions.register(name, renderer)
  if type(name) ~= "string" or name == "" then
    error("extension name must be a non-empty string", 2)
  end
  if type(renderer) ~= "table" or type(renderer.render) ~= "function" then
    error("extension must provide render(pass, time, width, height)", 2)
  end
  Extensions.registry[name] = renderer
end

function Extensions.get(name)
  return Extensions.registry[name]
end

function Extensions.new_state(name)
  local renderer = Extensions.get(name)
  if renderer and type(renderer.new) == "function" then
    return renderer.new()
  end
  return {}
end

function Extensions.reload(name)
  if type(name) ~= "string" then
    error("extension name must be a string", 2)
  end
  package.loaded["extensions." .. name] = nil
  local ok, renderer = pcall(require, "extensions." .. name)
  if not ok then
    return nil, renderer
  end
  Extensions.register(name, renderer)
  return renderer
end

Extensions.register("cube", require("extensions.cube"))

return Extensions
