--
-- Process-backed kernel supervisor.  One plain-LuaJIT child per notebook,
-- communicating through atomically renamed JSON job/result files.  This is a
-- Linux/macOS spike; the thread supervisor remains the default.
--
local json = require("notebook.json")

local ProcessSupervisor = {}
ProcessSupervisor.__index = ProcessSupervisor

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function ProcessSupervisor.new(options)
  options = options or {}
  return setmetatable({
    kernels = {},
    pending = {},
    next_id = 1,
    on_result = options.on_result,
    on_error = options.on_error,
    root = options.root or ".",
  }, ProcessSupervisor)
end

function ProcessSupervisor:open(id)
  if self.kernels[id] then return self.kernels[id] end
  local dir = string.format("/tmp/lua-notebooks-process-%d-%s",
    os.time(), tostring(id):gsub("[^%w_-]", "_"))
  os.execute("rm -rf " .. shell_quote(dir) .. " && mkdir -p " ..
    shell_quote(dir))
  local command = string.format(
    "LUANB_PROCESS_ROOT=%s luajit %s %s %s > %s 2>&1 &",
    shell_quote(self.root .. "/kernel/process_worker.lua"),
    shell_quote(self.root .. "/kernel/process_worker.lua"),
    shell_quote(dir), shell_quote(self.root),
    shell_quote(dir .. "/worker.log"))
  -- The environment assignment above is intentionally unused by the child;
  -- keep the command simple and portable.
  command = string.format("luajit %s %s %s > %s 2>&1 & echo $! > %s",
    shell_quote(self.root .. "/kernel/process_worker.lua"),
    shell_quote(dir), shell_quote(self.root),
    shell_quote(dir .. "/worker.log"), shell_quote(dir .. "/pid"))
  os.execute(command)
  local kernel = {
    id = id,
    dir = dir,
    job_path = dir .. "/job.json",
    result_path = dir .. "/result.json",
    ready_path = dir .. "/ready",
    pid_path = dir .. "/pid",
    status = "running",
  }
  self.kernels[id] = kernel
  return kernel
end

function ProcessSupervisor:_send(id, job)
  local kernel = self:open(id)
  if kernel.status ~= "running" then return nil, "kernel is not running" end
  local request = self.next_id
  self.next_id = request + 1
  job.id = request
  self.pending[request] = { kernel = id, job = job }
  local temporary = kernel.job_path .. ".tmp"
  local file = assert(io.open(temporary, "w"))
  file:write(json.encode(job))
  file:close()
  assert(os.rename(temporary, kernel.job_path))
  return request
end

function ProcessSupervisor:run(id, code, cell)
  return self:_send(id, { cell = cell, code = code })
end

function ProcessSupervisor:widget(id, cell, widget, event)
  return self:_send(id, { cell = cell, widget = widget, event = event })
end

function ProcessSupervisor:poll()
  for id, kernel in pairs(self.kernels) do
    local file = io.open(kernel.result_path, "r")
    if file then
      local data = file:read("*a")
      file:close()
      os.remove(kernel.result_path)
      local ok, message = pcall(json.decode, data)
      if ok and message and self.pending[message.id] then
        local request = self.pending[message.id]
        self.pending[message.id] = nil
        if self.on_result then self.on_result(id, request, message) end
      elseif self.on_error then
        self.on_error(id, "invalid result: " .. tostring(message))
      end
    end
  end
end

function ProcessSupervisor:threaderror() end

function ProcessSupervisor:stop(id)
  local kernel = self.kernels[id]
  if kernel == nil then return end
  local pid_file = io.open(kernel.pid_path, "r")
  if pid_file then
    local pid = pid_file:read("*a"):gsub("%s+", "")
    pid_file:close()
    if pid ~= "" then
      os.execute("kill " .. shell_quote(pid) .. " 2>/dev/null || true")
    end
  end
  os.execute("rm -rf " .. shell_quote(kernel.dir))
  self.kernels[id] = nil
end

function ProcessSupervisor:restart(id)
  self:stop(id)
  return self:open(id)
end

function ProcessSupervisor:close()
  for id in pairs(self.kernels) do
    self:stop(id)
  end
end

return ProcessSupervisor
