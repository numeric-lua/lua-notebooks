local root = (arg and arg[0] or "tests/types.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Types = require("notebook.lsp.types")

local function labels(items)
  local result = {}
  for _, item in ipairs(items or {}) do result[#result + 1] = item.label end
  table.sort(result)
  return table.concat(result, ",")
end

local source = [[
local config = { name = "nb", count = 1, nested = { enabled = true },
  run = function() end }
config.mode = "fast"
print(config.name)
config.
]]
local fields = Types.complete(source, #source)
assert(labels(fields) == "count,mode,name,nested,run", labels(fields))

local resolved = Types.resolve(source, source:find("config.name") + 7)
assert(resolved and resolved.type.kind == "string", resolved and resolved.type.kind)
assert(resolved.declaration and resolved.declaration.text == "name")

local nested = [[
local a = { b = { c = 42 } }
a.b.
]]
local nested_fields = Types.complete(nested, #nested)
assert(labels(nested_fields) == "c", labels(nested_fields))

local string_source = [[
local s = string.format("%d", 1)
s.
]]
local string_fields = Types.complete(string_source, #string_source)
assert(string_fields and #string_fields > 5, string_fields and #string_fields)
assert(labels(string_fields):find("format", 1, true))

local shadow = [[
local value = 1
do
  local value = { answer = 42 }
  value.
end
value.
]]
local first_dot = shadow:find("value%.\nend") or 1
local shadow_fields = Types.complete(shadow, first_dot + 6)
assert(labels(shadow_fields) == "answer", labels(shadow_fields))

local string_keys = [[
local config = { ["long-name"] = 1, ["with space"] = 2 }
config.
]]
local key_fields = Types.complete(string_keys, #string_keys)
assert(labels(key_fields) == "long-name,with space", labels(key_fields))

local methods = [[
local Module = {}
function Module:run() end
Module.
]]
local method_fields = Types.complete(methods, #methods)
assert(labels(method_fields) == "run", labels(method_fields))
local method_resolved = Types.resolve(methods, methods:find("Module.run") + 7)
assert(method_resolved and method_resolved.type.kind == "function")

local symbols = Types.symbols("local alpha = 1\nlocal beta = {}\n", 20)
assert(labels(symbols):find("alpha", 1, true))
assert(labels(symbols):find("beta", 1, true))
print("typed completion tests ok")
