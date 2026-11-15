--
-- lua-notebooks: a LÖVR-hosted notebook shell.
--
-- The host owns graphics and input.  Each notebook gets a persistent LÖVR
-- thread with its own Lua state; cells are evaluated there and results return
-- over named channels.  See notebook/supervisor.lua and kernel/worker.lua.
--
local Notebook = require("notebook.model")
local Supervisor = require("notebook.supervisor")
local Format = require("notebook.format")
local Extensions = require("extensions")
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
  local cell_token = self.active .. ":" .. index
  local request, err = self.supervisor:run("nb" .. self.active, cell.source,
    cell_token)
  if request == nil then
    cell.running = false
    self.status = "kernel error: " .. tostring(err)
    return
  end
  self.pending[request] = { notebook = self.active, cell = index,
    kind = "run" }
  self.status = "running " .. cell_label(index)
end

function App:on_result(kernel_id, request, message)
  local target = self.pending[message.id]
  self.pending[message.id] = nil
  if target == nil then return end
  local notebook = self.notebooks[target.notebook]
  if notebook == nil then return end
  if target.kind == "widget" then
    notebook:apply_widget_result(target.cell, message)
  else
    notebook:set_result(target.cell, message)
  end
  if message.ok == false then
    self.status = "error in " .. cell_label(target.cell)
  else
    self.status = "finished " .. cell_label(target.cell)
  end
end

function App:widget_event(cell_index, spec, event)
  local cell = self:notebook().cells[cell_index]
  if cell then cell.running = true end
  local cell_token = self.active .. ":" .. cell_index
  local request, err = self.supervisor:widget("nb" .. self.active, cell_token,
    spec.id, event)
  if request == nil then
    if cell then cell.running = false end
    self.status = "widget error: " .. tostring(err)
    return
  end
  self.pending[request] = { notebook = self.active, cell = cell_index,
    kind = "widget" }
  self.status = "widget " .. tostring(spec.id)
end

function App:reload_extension(id)
  local renderer, err = Extensions.reload(id)
  if renderer == nil then
    self.status = "reload failed: " .. tostring(err)
  else
    self.status = "reloaded " .. id .. " extension"
  end
end

function App:add_cell()
  self:notebook():add_cell("code")
  self.status = "new cell"
end

function App:save()
  local ok, path, absolute = pcall(Format.save, self:notebook())
  if not ok then
    self.status = "save failed: " .. tostring(path)
    return
  end
  self.status = "saved " .. tostring(absolute)
end

function App:load()
  local ok, loaded, err = pcall(Format.load, self:notebook().name)
  if not ok then
    self.status = "load failed: " .. tostring(loaded)
    return
  end
  if loaded == nil then
    self.status = "load failed: " .. tostring(err)
    return
  end
  self.notebooks[self.active] = loaded
  self.scroll = 0
  self.status = "loaded " .. loaded.name
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
  local loaded, errors = Extensions.discover()
  app.status = string.format("%d kernels, %d extensions",
    #app.notebooks, 1 + #loaded)
  if #errors > 0 then
    app.status = app.status .. "; " .. #errors .. " extension error(s)"
  end
  lovr.filesystem.watch()
  _G.app = app

  if os.getenv("LUANB_SMOKE_SAVE") then
    app:save()
    print("SMOKE_SAVED=" .. tostring(app.status))
    local loaded, err = Format.load(app:notebook().name)
    print("SMOKE_LOADED=" .. (loaded and loaded.name or tostring(err)))
    lovr.event.quit()
  end

  -- Non-interactive smoke path: run the first welcome cell, print its result,
  -- and quit.  This exercises thread startup, channels, the kernel worker, and
  -- result routing without requiring a human at the window.
  if os.getenv("LUANB_SMOKE") or os.getenv("LUANB_SMOKE_SCENE") or
     os.getenv("LUANB_SMOKE_PLOT") or os.getenv("LUANB_SMOKE_GRID") or
     os.getenv("LUANB_SMOKE_WIDGET") or
     os.getenv("LUANB_SMOKE_WIDGET_EVENT") then
    app.smoke = true
    app.smoke_start = lovr.timer.getTime()
    if os.getenv("LUANB_SMOKE_SCENE") then
      app:notebook():select(3)
    elseif os.getenv("LUANB_SMOKE_PLOT") then
      app:notebook():select(4)
    elseif os.getenv("LUANB_SMOKE_GRID") then
      app:notebook():select(5)
    elseif os.getenv("LUANB_SMOKE_WIDGET") or
           os.getenv("LUANB_SMOKE_WIDGET_EVENT") then
      app:notebook():select(6)
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
    if os.getenv("LUANB_SMOKE_WIDGET_EVENT") then
      if not app.smoke_widget_sent and #cell.widgets > 0 then
        app.smoke_widget_sent = true
        app:widget_event(6, cell.widgets[1],
          { type = "change", value = 7 })
      elseif app.smoke_widget_sent and not cell.running and
             lovr.timer.getTime() - app.smoke_start > 2 then
        print("SMOKE_OUTPUT=" .. cell.output)
        print("SMOKE_WIDGETS=" .. tostring(#cell.widgets))
        print("SMOKE_STATUS=" .. app.status)
        app.smoke = false
        lovr.event.quit()
      end
    else
      local done = not cell.running and
        (cell.output ~= "" or cell.scene ~= nil or #cell.widgets > 0)
      if done and lovr.timer.getTime() - app.smoke_start > 2 then
        print("SMOKE_OUTPUT=" .. cell.output)
        print("SMOKE_SCENE=" .. tostring(cell.scene))
        print("SMOKE_WIDGETS=" .. tostring(#cell.widgets))
        print("SMOKE_STATUS=" .. app.status)
        app.smoke = false
        lovr.event.quit()
      end
    end
  end
end

function lovr.draw(pass)
  if app == nil then return end
  local passes
  if app.smoke then
    local ok, result = pcall(app.ui.draw, app.ui, pass)
    if not ok then
      print("SMOKE_DRAW_ERROR=" .. tostring(result))
      app.smoke = false
      lovr.event.quit()
      return
    end
    passes = result
  else
    passes = app.ui:draw(pass)
  end
  passes[#passes + 1] = pass
  return lovr.graphics.submit(passes)
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

function lovr.mousemoved(x, y, dx, dy)
  if app then app.ui:mousemoved(x, y, dx, dy) end
end

function lovr.mousereleased(x, y, button)
  if app then app.ui:mousereleased(x, y, button) end
end

function lovr.wheelmoved(dx, dy)
  if app then app.ui:wheelmoved(dy) end
end

function lovr.threaderror(thread, message)
  if app then app.supervisor:threaderror(thread, message) end
end

function lovr.filechanged(path, action)
  local id = path:match("^extensions/([a-z][a-z0-9_-]*)%.lua$")
  if app and id and id ~= "init" and id ~= "loader" and id ~= "manifest" then
    app:reload_extension(id)
  end
end
