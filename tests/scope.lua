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
local shadowed = [=[
local x = 1
do
  local x = 2
  print(x)
end
print(x)
]=]
local analysis = Scope.analyze(shadowed)
local ranges = Scope.resolved_ranges(shadowed, shadowed:find("x = 2", 1, true), "x")
assert(ranges and #ranges == 2, ranges and #ranges)
local outer_ranges = Scope.resolved_ranges(shadowed,
  shadowed:find("x = 1", 1, true), "x")
assert(outer_ranges and #outer_ranges == 2, outer_ranges and #outer_ranges)
print("scope tests ok")
