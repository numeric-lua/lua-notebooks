--
-- lua-notebooks: a LÖVR-hosted notebook shell.
--
-- The host owns graphics and input.  Each notebook gets a persistent LÖVR
-- thread with its own Lua state; cells are evaluated there and results return
-- over named channels.  See notebook/supervisor.lua and kernel/worker.lua.
--
local Notebook = require("notebook.model")
local Supervisor = require("notebook.supervisor")
local ProcessSupervisor = require("notebook.process_supervisor")
local Format = require("notebook.format")
local Extensions = require("extensions")
local UI = require("ui.notebook")
local LspClient = require("notebook.lsp_client")

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
    vim_mode = true,
    lsp = nil,
    lsp_thread = nil,
    lsp_in = lovr.thread.getChannel("lua-notebooks:lsp:in"),
    lsp_out = lovr.thread.getChannel("lua-notebooks:lsp:out"),
  }, App)
  self.lsp_thread = lovr.thread.newThread("notebook/lsp_worker.lua")
  self.lsp_thread:start("lua-notebooks:lsp:in", "lua-notebooks:lsp:out")
  self.lsp = LspClient.new({
    send = function(bytes) self.lsp_in:push(bytes) end,
    on_initialized = function() self.lsp_ready = true end,
    on_diagnostics = function(uri, items) self.lsp_diagnostics[uri] = items end,
  })
  self.lsp_diagnostics = {}
  self.lsp:initialize("luanb:///")
  local process_requested = os.getenv("LUANB_KERNEL_MODE") == "process"
  if process_requested and not ProcessSupervisor.supported() then
    print("process kernels are unavailable on this platform; using threads")
    process_requested = false
  end
  local SupervisorClass = process_requested and ProcessSupervisor or Supervisor
  self.supervisor = SupervisorClass.new({
    root = lovr.filesystem.getSource(),
    memory_kb = tonumber(os.getenv("LUANB_KERNEL_MEMORY_KB") or "") or 524288,
    cpu_seconds = tonumber(os.getenv("LUANB_KERNEL_CPU_SECONDS") or "") or 12,
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

function App:ensure_canvas(width, height)
  if self.canvas and self.canvas_width == width and self.canvas_height == height then
    return self.canvas, self.canvas_pass
  end
  self.canvas = lovr.graphics.newTexture(width, height, {
    format = "rgba8", mipmaps = false, samples = 1,
    usage = { "sample", "render", "transfer" },
  })
  self.canvas_pass = lovr.graphics.newPass(self.canvas)
  self.canvas_width, self.canvas_height = width, height
  return self.canvas, self.canvas_pass
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

function App:server_diagnostic(cell)
  local uri = "luanb:///notebooks/" .. self:notebook().name .. "?cell=" ..
    tostring(cell.id)
  local items = self.lsp_diagnostics and self.lsp_diagnostics[uri]
  return items and items[1] or nil
end

function App:library_items()
  self.tree_expanded = self.tree_expanded or { notebooks = true }
  return Format.list_tree(self.tree_expanded)
end

function App:new_notebook()
  local index = 1
  while Format.load("untitled-" .. index .. ".luanb") do index = index + 1 end
  local name = "untitled-" .. index .. ".luanb"
  local notebook = Notebook.new({
    name = name,
    cells = { { kind = "code", source = "print('new notebook')" } },
  })
  Format.save(notebook)
  notebook._path = "notebooks/" .. name
  self.notebooks[#self.notebooks + 1] = notebook
  self.active = #self.notebooks
  self.supervisor:open("nb" .. self.active)
  self.status = "created " .. name
end

function App:create_folder(name)
  local path, err = Format.create_folder(name)
  if path == nil then self.status = "folder failed: " .. tostring(err); return end
  self.tree_expanded[path] = true
  self.status = "created " .. path
end

function App:rename_notebook(old_path, new_name)
  local new_path, err = Format.rename_path(old_path, new_name)
  if new_path == nil then
    self.status = "rename failed: " .. tostring(err)
    return
  end
  local basename = new_path:match("([^/]+)$")
  for _, notebook in ipairs(self.notebooks) do
    if notebook._path == old_path then
      notebook._path = new_path
      notebook.name = basename
      break
    end
  end
  self.status = "renamed to " .. new_path
end

function App:delete_notebook(path)
  local ok, err = Format.delete_path(path)
  if not ok then self.status = "delete failed: " .. tostring(err); return end
  for index, notebook in ipairs(self.notebooks) do
    if notebook._path == path then table.remove(self.notebooks, index); break end
  end
  self.active = math.max(1, math.min(self.active, #self.notebooks))
  self.status = "deleted " .. path
end

function App:open_path(path)
  local existing
  for index, notebook in ipairs(self.notebooks) do
    if notebook._path == path then existing = index; break end
  end
  if existing then
    self:set_tab(existing)
    return
  end
  local notebook, err = Format.load_path(path)
  if notebook == nil then
    self.status = "open failed: " .. tostring(err)
    return
  end
  self.notebooks[#self.notebooks + 1] = notebook
  self.active = #self.notebooks
  self.supervisor:open("nb" .. self.active)
  self.status = "opened " .. name
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
    kind = "run", started = lovr.timer.getTime() }
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
    kind = "widget", started = lovr.timer.getTime() }
  self.status = "widget " .. tostring(spec.id)
end

function App:reload_user_extensions()
  local loaded, errors = Extensions.discover_user()
  self.status = string.format("loaded %d user extension(s)", #loaded)
  if #errors > 0 then
    self.status = self.status .. "; " .. #errors .. " error(s)"
  end
end

function App:reload_extension(id)
  local renderer, err = Extensions.reload(id)
  if renderer then self.last_reload = id end
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
  if self.screenshot_readback and self.screenshot_readback:isComplete() then
    local image = self.screenshot_readback:getImage()
    self.screenshot_readback = nil
    if image and image:getFormat() == "rgba8" then
      local blob = image:encode()
      lovr.filesystem.createDirectory("screenshots")
      local path = "screenshots/notebook-" .. tostring(os.time()) .. ".png"
      lovr.filesystem.write(path, blob:getString())
      self.status = "screenshot " .. path
      print("SCREENSHOT=" .. path)
      if self.qa_screenshot then lovr.event.quit() end
    end
  end
  if self.qa_screenshot and not self.screenshot_requested and
     not self.screenshot_readback and lovr.timer.getTime() > 2 then
    self.screenshot_requested = true
  end
  if os.getenv("LUANB_LSP_SMOKE") and self.lsp_ready and
     not self.lsp_smoke_done then
    self.lsp_smoke_done = true
    print("SMOKE_LSP=ready")
    lovr.event.quit()
  end
  if self.lsp then
    while true do
      local bytes = self.lsp_out:pop(false)
      if bytes == nil then break end
      local messages = require("notebook.lsp.framing").new_decoder():feed(bytes)
      for _, message in ipairs(messages) do self.lsp:handle(message) end
    end
    self.lsp:sync(self:notebook(), "notebooks/" .. self:notebook().name)
  end
  if self.qa_complete and self.ui.width and not self.qa_completion_opened then
    self.qa_completion_opened = true
    self.ui:open_completion()
  end
  if self.smoke_watch then
    local elapsed = lovr.timer.getTime() - self.smoke_watch_started
    if elapsed > 1 and not self.smoke_watch_touched then
      self.smoke_watch_touched = true
      os.execute("cp extensions/cube.lua /tmp/luanb-cube-watch.bak && " ..
        "printf '\n-- watch probe\n' >> extensions/cube.lua")
    elseif self.smoke_watch_touched and self.last_reload == "cube" then
      print("SMOKE_WATCH=ok")
      self.smoke_watch = false
      lovr.event.quit()
    elseif elapsed > 6 then
      print("SMOKE_WATCH=timeout")
      self.smoke_watch = false
      lovr.event.quit()
    end
  end
  local now = lovr.timer.getTime()
  for request, target in pairs(self.pending) do
    if now - (target.started or now) > 8 then
      self.pending[request] = nil
      local notebook = self.notebooks[target.notebook]
      local cell = notebook and notebook.cells[target.cell]
      if cell then
        cell.running = false
        cell.error = "kernel did not answer (timeout)"
      end
      if self.supervisor.restart then
        self.supervisor:restart("nb" .. target.notebook)
        self.status = "kernel restarted after timeout in " .. cell_label(target.cell)
      else
        self.status = "kernel timeout in " .. cell_label(target.cell)
      end
    end
  end
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
  local user_loaded, user_errors = Extensions.discover_user()
  Extensions.load_preferences()
  app.status = string.format("%d kernels, %d extensions, %d user",
    #app.notebooks, 1 + #loaded, #user_loaded)
  if #errors + #user_errors > 0 then
    app.status = app.status .. "; " ..
      (#errors + #user_errors) .. " extension error(s)"
  end
  lovr.filesystem.watch()
  _G.app = app
  if os.getenv("LUANB_SMOKE_SUBST") then
    local cell = app:notebook():selected()
    cell.source = "hello hello"
    cell.cursor = #cell.source + 1
    app.ui.vim_normal = true
    app.ui:run_vim_command("s/hello/hi/g")
    print("SMOKE_SUBST=" .. cell.source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMSEARCH") then
    app.ui.vim_normal = true
    app.ui:keypressed("/")
    app.ui:textinput("grid")
    app.ui:keypressed("return")
    print("SMOKE_VIMSEARCH=" .. tostring(app.status))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMCMD") then
    app.ui.vim_normal = true
    app.ui:keypressed(":")
    app.ui:textinput("w")
    app.ui:keypressed("return")
    print("SMOKE_VIMCMD=" .. tostring(app.status))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_TYPE") then
    app.ui:textinput("X")
    local typed = app:notebook():selected().source:match("X$") ~= nil
    app.ui:keypressed("backspace")
    local removed = app:notebook():selected().source:match("X$") == nil
    print("SMOKE_TYPE=" .. tostring(typed and removed))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_FOLDER") then
    local path, err = Format.create_folder("folder-smoke")
    print("SMOKE_FOLDER=" .. tostring(path) .. " err=" .. tostring(err))
    os.remove(lovr.filesystem.getSaveDirectory() .. "/" .. tostring(path))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_RENAME") then
    app:new_notebook()
    local old = app:notebook()._path
    app:rename_notebook(old, "renamed-smoke")
    local new = app:notebook().name
    print("SMOKE_RENAME=" .. old .. "->" .. new)
    app:delete_notebook(app:notebook()._path)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_TREE") then
    local before = #Format.list()
    app:new_notebook()
    local name = app:notebook().name
    local path = app:notebook()._path
    local after = #Format.list()
    app:delete_notebook(path)
    local final = #Format.list()
    print(string.format("SMOKE_TREE=%d->%d->%d", before, after, final))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_EXT_PREFS") then
    Extensions.set_enabled("grid", false)
    Extensions.save_preferences()
    Extensions.disabled = {}
    Extensions.load_preferences()
    print("SMOKE_EXT_PREFS=" .. tostring(not Extensions.is_enabled("grid")))
    Extensions.set_enabled("grid", true)
    Extensions.save_preferences()
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_USER_EXT") then
    local loaded, errors = Extensions.discover_user()
    print("SMOKE_USER_EXT=" .. #loaded .. " errors=" .. #errors)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_WATCH") then
    app.smoke_watch = true
    app.smoke_watch_started = lovr.timer.getTime()
    app.smoke_watch_touched = false
  end

  -- Visual QA/demo: select and run one cell, then leave the window open.
  if os.getenv("LUANB_QA_SCREENSHOT") then
    app.qa_screenshot = true
  end
  if os.getenv("LUANB_QA_SCREENSHOT") then
    app.qa_screenshot = true
  end
  if os.getenv("LUANB_QA_ZEN") then
    app.ui.zen_mode = true
  end
  if os.getenv("LUANB_QA_COMPLETE") then
    app.qa_complete = true
  end
  if os.getenv("LUANB_QA_EXT") then
    app.ui.show_extensions = true
  end
  if os.getenv("LUANB_QA_TREE") then
    app.ui.show_tree = true
  end
  if os.getenv("LUANB_QA_VIM") then
    app.ui.vim_normal = true
    app.ui.vim_char_visual = true
    app.ui.vim_char_anchor = 1
    local cell = app:notebook():selected()
    cell.cursor = math.min(18, #cell.source + 1)
  end
  local qa_cell = tonumber(os.getenv("LUANB_QA_CELL") or "")
  if qa_cell then
    app:notebook():select(qa_cell)
    app:run()
  end

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
  if os.getenv("LUANB_SMOKE_SUBST") then
    local cell = app:notebook():selected()
    cell.source = "hello hello"
    cell.cursor = #cell.source + 1
    app.ui.vim_normal = true
    app.ui:run_vim_command("s/hello/hi/g")
    print("SMOKE_SUBST=" .. cell.source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMSEARCH") then
    app.ui.vim_normal = true
    app.ui:keypressed("/")
    app.ui:textinput("grid")
    app.ui:keypressed("return")
    print("SMOKE_VIMSEARCH=" .. tostring(app.status))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMCMD") then
    app.ui.vim_normal = true
    app.ui:keypressed(":")
    app.ui:textinput("w")
    app.ui:keypressed("return")
    print("SMOKE_VIMCMD=" .. tostring(app.status))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_TYPE") then
    app.ui:textinput("X")
    local typed = app:notebook():selected().source:match("X$") ~= nil
    app.ui:keypressed("backspace")
    local removed = app:notebook():selected().source:match("X$") == nil
    print("SMOKE_TYPE=" .. tostring(typed and removed))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_FOLDER") then
    local path, err = Format.create_folder("folder-smoke")
    print("SMOKE_FOLDER=" .. tostring(path) .. " err=" .. tostring(err))
    os.remove(lovr.filesystem.getSaveDirectory() .. "/" .. tostring(path))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_RENAME") then
    app:new_notebook()
    local old = app:notebook()._path
    app:rename_notebook(old, "renamed-smoke")
    local new = app:notebook().name
    print("SMOKE_RENAME=" .. old .. "->" .. new)
    app:delete_notebook(app:notebook()._path)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_TREE") then
    local before = #Format.list()
    app:new_notebook()
    local name = app:notebook().name
    local path = app:notebook()._path
    local after = #Format.list()
    app:delete_notebook(path)
    local final = #Format.list()
    print(string.format("SMOKE_TREE=%d->%d->%d", before, after, final))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_EXT_PREFS") then
    Extensions.set_enabled("grid", false)
    Extensions.save_preferences()
    Extensions.disabled = {}
    Extensions.load_preferences()
    print("SMOKE_EXT_PREFS=" .. tostring(not Extensions.is_enabled("grid")))
    Extensions.set_enabled("grid", true)
    Extensions.save_preferences()
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_USER_EXT") then
    local loaded, errors = Extensions.discover_user()
    print("SMOKE_USER_EXT=" .. #loaded .. " errors=" .. #errors)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_WATCH") then
    -- handled in update, after the watcher is installed
  elseif os.getenv("LUANB_SMOKE_RELOAD") then
    local renderer, err = Extensions.reload("cube")
    print("SMOKE_RELOAD=" .. (renderer and "ok" or tostring(err)))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_PROCESS_CRASH") then
    app.smoke = true
    app.smoke_start = lovr.timer.getTime()
    local notebook = app:notebook()
    notebook:add_cell("code")
    notebook:selected().source = "os.exit(1)"
    app:run()
  elseif os.getenv("LUANB_SMOKE") or os.getenv("LUANB_SMOKE_SCENE") or
     os.getenv("LUANB_SMOKE_PLOT") or os.getenv("LUANB_SMOKE_GRID") or
     os.getenv("LUANB_SMOKE_WIDGET") or
     os.getenv("LUANB_SMOKE_WIDGET_EVENT") or
     os.getenv("LUANB_SMOKE_INPUT") then
    app.smoke = true
    app.smoke_start = lovr.timer.getTime()
    if os.getenv("LUANB_SMOKE_SCENE") then
      app:notebook():select(3)
    elseif os.getenv("LUANB_SMOKE_PLOT") then
      app:notebook():select(4)
    elseif os.getenv("LUANB_SMOKE_GRID") then
      app:notebook():select(5)
    elseif os.getenv("LUANB_SMOKE_INPUT") then
      app:notebook():select(3)
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
    if os.getenv("LUANB_SMOKE_SUBST") then
    local cell = app:notebook():selected()
    cell.source = "hello hello"
    cell.cursor = #cell.source + 1
    app.ui.vim_normal = true
    app.ui:run_vim_command("s/hello/hi/g")
    print("SMOKE_SUBST=" .. cell.source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMSEARCH") then
    app.ui.vim_normal = true
    app.ui:keypressed("/")
    app.ui:textinput("grid")
    app.ui:keypressed("return")
    print("SMOKE_VIMSEARCH=" .. tostring(app.status))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMCMD") then
    app.ui.vim_normal = true
    app.ui:keypressed(":")
    app.ui:textinput("w")
    app.ui:keypressed("return")
    print("SMOKE_VIMCMD=" .. tostring(app.status))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_TYPE") then
    app.ui:textinput("X")
    local typed = app:notebook():selected().source:match("X$") ~= nil
    app.ui:keypressed("backspace")
    local removed = app:notebook():selected().source:match("X$") == nil
    print("SMOKE_TYPE=" .. tostring(typed and removed))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_FOLDER") then
    local path, err = Format.create_folder("folder-smoke")
    print("SMOKE_FOLDER=" .. tostring(path) .. " err=" .. tostring(err))
    os.remove(lovr.filesystem.getSaveDirectory() .. "/" .. tostring(path))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_RENAME") then
    app:new_notebook()
    local old = app:notebook()._path
    app:rename_notebook(old, "renamed-smoke")
    local new = app:notebook().name
    print("SMOKE_RENAME=" .. old .. "->" .. new)
    app:delete_notebook(app:notebook()._path)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_TREE") then
    local before = #Format.list()
    app:new_notebook()
    local name = app:notebook().name
    local path = app:notebook()._path
    local after = #Format.list()
    app:delete_notebook(path)
    local final = #Format.list()
    print(string.format("SMOKE_TREE=%d->%d->%d", before, after, final))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_EXT_PREFS") then
    Extensions.set_enabled("grid", false)
    Extensions.save_preferences()
    Extensions.disabled = {}
    Extensions.load_preferences()
    print("SMOKE_EXT_PREFS=" .. tostring(not Extensions.is_enabled("grid")))
    Extensions.set_enabled("grid", true)
    Extensions.save_preferences()
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_USER_EXT") then
    local loaded, errors = Extensions.discover_user()
    print("SMOKE_USER_EXT=" .. #loaded .. " errors=" .. #errors)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_WATCH") then
    -- handled in update, after the watcher is installed
  elseif os.getenv("LUANB_SMOKE_RELOAD") then
    local renderer, err = Extensions.reload("cube")
    print("SMOKE_RELOAD=" .. (renderer and "ok" or tostring(err)))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_PROCESS_CRASH") then
      if not cell.running and lovr.timer.getTime() - app.smoke_start > 6 then
        print("SMOKE_CRASH_RECOVERED=" .. tostring(cell.error))
        app.smoke = false
        lovr.event.quit()
      end
    elseif os.getenv("LUANB_SMOKE_INPUT") then
      if not app.smoke_input_sent and cell.scene == "cube" and
         next(app.ui.scene_rects) then
        local _, rect = next(app.ui.scene_rects)
        local before = rect.surface.state.yaw or 0.6
        app.ui:mousepressed(rect.x + 20, rect.y + 20, 1)
        app.ui:mousemoved(rect.x + 50, rect.y + 35, 30, 15)
        app.ui:mousereleased(rect.x + 50, rect.y + 35, 1)
        local after = rect.surface.state.yaw or 0.6
        print("SMOKE_INPUT_YAW_CHANGED=" .. tostring(before ~= after))
        app.smoke_input_sent = true
      elseif app.smoke_input_sent and
             lovr.timer.getTime() - app.smoke_start > 1 then
        app.smoke = false
        lovr.event.quit()
      end
    elseif os.getenv("LUANB_SMOKE_WIDGET_EVENT") then
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

function lovr.draw(window)
  if app == nil then return end
  local width, height = window:getDimensions()
  local canvas, canvas_pass = app:ensure_canvas(width, height)
  if app.screenshot_requested then
    app.screenshot_requested = false
    app.screenshot_readback = canvas:newReadback()
  end
  local passes = app.ui:draw(canvas_pass)
  window:fill(canvas)
  passes[#passes + 1] = canvas_pass
  passes[#passes + 1] = window
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

function lovr.quit()
  if app and app.supervisor.close then app.supervisor:close() end
  if app and app.lsp_in then app.lsp_in:push("__quit") end
end

function lovr.filechanged(path, action)
  local id = path:match("extensions/([a-z][a-z0-9_-]*)%.lua$")
  if app and id and id ~= "init" and id ~= "loader" and id ~= "manifest" then
    app:reload_extension(id)
  end
end
