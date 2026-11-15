local root = (arg and arg[0] or "tests/scope.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Scope = require("notebook.lsp.scope")
local source = [=[
local old = "old"
print(old, object.old, other:old())
-- old in a comment
local long = [[ old ]]
]=]
local occurrences = Scope.occurrences(source, "old")
assert(#occurrences == 2, #occurrences)
assert(source:sub(occurrences[1].start, occurrences[1].finish) == "old")
print("scope tests ok")
