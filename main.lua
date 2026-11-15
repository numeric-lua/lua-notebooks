--
-- lua-notebooks: a LÖVR-hosted notebook shell.
--
-- The host owns graphics and input.  Each notebook gets a persistent LÖVR
-- thread with its own Lua state; cells are evaluated there and results return
-- over named channels.  See notebook/supervisor.lua and kernel/worker.lua.
--
local Notebook = require("notebook.model")
local Supervisor = require("notebook.supervisor")
local UI = require("ui.notebook")

local App = {}
App.__index = App

local function cell_label(index)
  return string.format("In [%d]", index)
end

function App:new(notebooks)
  local self = setmetatable({
    notebooks = notebooks,
    active = 1,
    scroll = 0,
    status = "ready",
    pending = {},
    ui = nil,
    font = nil,
    title_font = nil,
    supervisor = nil,
  }, App)
  self.supervisor = Supervisor.new({
    on_result = function(kernel_id, request, message)
      self:on_result(kernel_id, request, message)
    end,
    on_error = function(kernel_id, message)
      self.status = "kernel " .. tostring(kernel_id) .. " error: " .. tostring(message)
      print("KERNEL_ERROR=" .. tostring(message))
    end,
  })
  return self
end

function App:notebook()
  return self.notebooks[self.active]
end

function App:set_tab(index)
  if index < 1 or index > #self.notebooks then return end
  self.active = index
  self.scroll = 0
  self.status = self.notebooks[index].name
end

function App:open_all_kernels()
  for index = 1, #self.notebooks do
    self.supervisor:open("nb" .. index)
  end
end

function App:run()
  local notebook = self:notebook()
  local index = notebook.active
  local cell = notebook.cells[index]
  if cell.kind ~= "code" then
    self.status = "markdown cells are not executable"
    return
  end
  if cell.running then
    self.status = "cell is already running"
    return
  end
  cell.running = true
  cell.output = ""
  cell.error = nil
  cell.scene = nil
  local request, err = self.supervisor:run("nb" .. self.active, cell.source)
  if request == nil then
    cell.running = false
    self.status = "kernel error: " .. tostring(err)
    return
  end
  self.pending[request] = { notebook = self.active, cell = index }
  self.status = "running " .. cell_label(index)
end

function App:on_result(kernel_id, request, message)
  local target = self.pending[message.id]
  self.pending[message.id] = nil
  if target == nil then return end
  local notebook = self.notebooks[target.notebook]
  if notebook == nil then return end
  notebook:set_result(target.cell, message)
  if message.ok == false then
    self.status = "error in " .. cell_label(target.cell)
  else
    self.status = "finished " .. cell_label(target.cell)
  end
end

function App:add_cell()
  self:notebook():add_cell("code")
  self.status = "new cell"
end

function App:update()
  self.supervisor:poll()
end

function lovr.load()
  local app = App:new(Notebook.demo())
  app.font = lovr.graphics.newFont(18)
  app.font:setPixelDensity(1)
  app.title_font = lovr.graphics.newFont(22)
  app.title_font:setPixelDensity(1)
  app.ui = UI.new(app)
  app:open_all_kernels()
  app.status = "two kernels ready"
  _G.app = app

  -- Non-interactive smoke path: run the first welcome cell, print its result,
  -- and quit.  This exercises thread startup, channels, the kernel worker, and
  -- result routing without requiring a human at the window.
  if os.getenv("LUANB_SMOKE") or os.getenv("LUANB_SMOKE_SCENE") then
    app.smoke = true
    app.smoke_start = lovr.timer.getTime()
    if os.getenv("LUANB_SMOKE_SCENE") then
      app:notebook():select(3)
    end
    app:run()
  end
end

function lovr.update(dt)
  if app == nil then return end
  app:update()
  if app.smoke then
    local notebook = app:notebook()
    local cell = notebook.cells[notebook.active]
    local done = not cell.running and
      (cell.output ~= "" or cell.scene ~= nil)
    if done and lovr.timer.getTime() - app.smoke_start > 2 then
      print("SMOKE_OUTPUT=" .. cell.output)
      print("SMOKE_SCENE=" .. tostring(cell.scene))
      print("SMOKE_STATUS=" .. app.status)
      app.smoke = false
      lovr.event.quit()
    end
  end
end

function lovr.draw(pass)
  if app == nil then return end
  if app.smoke then
    local ok, err = pcall(app.ui.draw, app.ui, pass)
    if not ok then
      print("SMOKE_DRAW_ERROR=" .. tostring(err))
      app.smoke = false
      lovr.event.quit()
    end
  else
    app.ui:draw(pass)
  end
end

function lovr.textinput(text, code)
  if app then app.ui:textinput(text) end
end

function lovr.keypressed(key)
  if app then app.ui:keypressed(key) end
end

function lovr.mousepressed(x, y, button)
  if app then app.ui:mousepressed(x, y, button) end
end

function lovr.wheelmoved(dx, dy)
  if app then app.ui:wheelmoved(dy) end
end

function lovr.threaderror(thread, message)
  if app then app.supervisor:threaderror(thread, message) end
end
