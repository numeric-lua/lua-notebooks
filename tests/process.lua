local root = (arg and arg[0] or "tests/process.lua"):match("^(.*)/tests/") or "."
local ProcessSupervisor = require("notebook.process_supervisor")
local seen
local supervisor = ProcessSupervisor.new({
  root = root,
  on_result = function(id, request, message) seen = message end,
})
local request, err = supervisor:run("test", "print('process hello')", "1:1")
assert(request, err)
for _ = 1, 300 do
  supervisor:poll()
  if seen then break end
  os.execute("sleep 0.01")
end
assert(seen, "process kernel did not answer")
assert(seen.ok, seen.value)
assert(seen.output:find("process hello", 1, true), seen.output)
assert(type(seen.elapsed) == "number" and seen.elapsed >= 0,
  "process result has elapsed seconds")
print("process kernel ok")
supervisor:close()
