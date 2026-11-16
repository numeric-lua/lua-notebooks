--
-- Starts one persistent LÖVR thread per notebook and routes cell jobs over
-- named channels.  Kernel threads never touch lovr.graphics; they only return
-- text/scene descriptions.
--
local Supervisor = {}
Supervisor.__index = Supervisor

function Supervisor.new(options)
  options = options or {}
  return setmetatable({
    kernels = {},
    pending = {},
    next_id = 1,
    root = options.root or ".",
    on_result = options.on_result,
    on_error = options.on_error,
  }, Supervisor)
end

function Supervisor:open(id)
  if self.kernels[id] then return self.kernels[id] end
  local in_name = "lua-notebooks:" .. id .. ":in"
  local out_name = "lua-notebooks:" .. id .. ":out"
  local thread = lovr.thread.newThread("kernel/worker.lua")
  thread:start(in_name, out_name, self.root)
  local kernel = {
    id = id,
    in_channel = lovr.thread.getChannel(in_name),
    out_channel = lovr.thread.getChannel(out_name),
    thread = thread,
    status = "running",
  }
  self.kernels[id] = kernel
  return kernel
end

function Supervisor:_request(id, job)
  local kernel = self:open(id)
  if kernel.status ~= "running" then
    return nil, "kernel is not running"
  end
  local request = self.next_id
  self.next_id = request + 1
  self.pending[request] = { kernel = id, job = job }
  job.id = request
  kernel.in_channel:push(job)
  return request
end

function Supervisor:run(id, code, cell)
  return self:_request(id, { cell = cell, code = code })
end

function Supervisor:widget(id, cell, widget, event)
  return self:_request(id, {
    cell = cell,
    widget = widget,
    event = event,
  })
end

function Supervisor:poll()
  for id, kernel in pairs(self.kernels) do
    while true do
      local message = kernel.out_channel:pop(false)
      if message == nil then break end
      local request = self.pending[message.id]
      self.pending[message.id] = nil
      if self.on_result then
        self.on_result(id, request, message)
      end
    end
    if kernel.thread and not kernel.thread:isRunning() then
      kernel.status = "stopped"
    end
  end
end

function Supervisor:threaderror(thread, message)
  for id, kernel in pairs(self.kernels) do
    if kernel.thread == thread then
      kernel.status = "error"
      if self.on_error then self.on_error(id, message) end
    end
  end
end

function Supervisor:close()
  for _, kernel in pairs(self.kernels) do
    if kernel.status == "running" then
      kernel.in_channel:push("__quit")
    end
  end
end

return Supervisor
