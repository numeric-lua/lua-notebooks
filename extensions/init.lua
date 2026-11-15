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

Extensions.register("cube", require("extensions.cube"))

return Extensions
