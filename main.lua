--
-- lua-notebooks: a LÖVR-hosted notebook shell.
--
-- The host owns graphics and input.  On desktop each notebook gets a
-- persistent LÖVR thread with its own Lua state; on web/WASM, where LÖVR
-- disables threads, cells run inline through the same Lua 5.1-safe engine.
-- See notebook/supervisor.lua, notebook/inline_supervisor.lua, and
-- kernel/engine.lua.
--
local Notebook = require("notebook.model")
local NvimBuffer = require("notebook.nvim.buffer")
local Supervisor = require("notebook.supervisor")
local InlineSupervisor = require("notebook.inline_supervisor")
local ProcessSupervisor = require("notebook.process_supervisor")
local RemoteSupervisor = require("notebook.remote_supervisor")
local Runtime = require("notebook.runtime")
local Format = require("notebook.format")
local Extensions = require("extensions")
local UI = require("ui.notebook")
local Theme = require("ui.theme")
local LspClient = require("notebook.lsp_client")
local LspEdits = require("notebook.lsp_edits")

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
    kernel_keys = setmetatable({}, { __mode = "k" }),
    next_kernel_key = 1,
    ui = nil,
    font = nil,
    title_font = nil,
    supervisor = nil,
    vim_mode = true,
    lsp = nil,
    lsp_thread = nil,
    lsp_in = nil,
    lsp_out = nil,
  }, App)
  self.lsp_diagnostics = {}
  if Runtime.has_threads() then
    self.lsp_in = lovr.thread.getChannel("lua-notebooks:lsp:in")
    self.lsp_out = lovr.thread.getChannel("lua-notebooks:lsp:out")
    self.lsp_thread = lovr.thread.newThread("notebook/lsp_worker.lua")
    self.lsp_thread:start("lua-notebooks:lsp:in", "lua-notebooks:lsp:out")
    self.lsp = LspClient.new({
      send = function(bytes) self.lsp_in:push(bytes) end,
      on_initialized = function() self.lsp_ready = true end,
      on_diagnostics = function(uri, items) self.lsp_diagnostics[uri] = items end,
    })
    self.lsp:initialize("luanb:///")
  end
  self.ui_scale = 1
  self.nvim_inline = false
  self.nvim_inline_original = nil
  self._nvim_undo_started = false
  self._nvim_sync_at = 0
  self._nvim_pending_hide = false
  self._nvim_hidden_cell = nil
  self.nvim_delete_prompt = nil
  self.autosave_at = 0
  self.closed_notebooks = {}
  self.recent_paths = {}
  local recent_ok, recent_text = pcall(lovr.filesystem.read, "recent.json")
  if recent_ok and recent_text then
    self.recent_paths = Format.decode_recent(recent_text)
  end
  local scale_ok, scale_value = pcall(lovr.filesystem.read, "ui_scale.txt")
  if scale_ok and tonumber(scale_value) then
    self.ui_scale = math.max(0.7, math.min(2, tonumber(scale_value)))
  end
  self.tree_expanded = { notebooks = true }
  self.tree_sort = "name"
  local sort_ok, sort_value = pcall(lovr.filesystem.read, "tree_sort.txt")
  if sort_ok and (sort_value == "name" or sort_value == "name-desc" or
      sort_value == "recent") then
    self.tree_sort = sort_value
  end
  local kernel_mode = os.getenv("LUANB_KERNEL_MODE")
  local remote_url = os.getenv("LUANB_REMOTE_URL")
  if remote_url == nil and Runtime.is_web() then
    local ok, value = pcall(lovr.filesystem.read, "remote.txt")
    if ok and value then remote_url = value:gsub("%s+$", "") end
  end
  local process_requested = kernel_mode == "process"
  if process_requested and not ProcessSupervisor.supported() then
    print("process kernels are unavailable on this platform; using inline")
    process_requested = false
  end
  local remote_requested = kernel_mode == "remote" or
    (Runtime.is_web() and remote_url ~= nil)
  local remote_transport = nil
  if remote_requested then
    if remote_url == nil then
      print("remote kernels require LUANB_REMOTE_URL or remote.txt")
    elseif Runtime.is_web() then
      local ok, transport = pcall(function()
        return require("notebook.browser_transport").new(remote_url)
      end)
      if ok then remote_transport = transport
      else print("browser WebSocket bridge unavailable: " .. tostring(transport)) end
    elseif Runtime.has_ffi() then
      local ok, transport = pcall(function()
        return require("notebook.websocket_transport").new(remote_url)
      end)
      if ok then remote_transport = transport
      else print("remote kernel connection failed: " .. tostring(transport)) end
    else
      print("remote kernels require LuaJIT ffi")
    end
  end
  local inline_requested = kernel_mode == "inline" or
    (not remote_transport and not Runtime.has_threads())
  local on_result = function(kernel_id, request, message)
    self:on_result(kernel_id, request, message)
  end
  local on_error = function(kernel_id, message)
    self.status = "kernel " .. tostring(kernel_id) .. " error: " ..
      tostring(message)
    print("KERNEL_ERROR=" .. tostring(message))
  end
  if remote_transport then
    self.supervisor = RemoteSupervisor.new({
      transport = remote_transport,
      on_result = on_result,
      on_error = on_error,
    })
  else
    local SupervisorClass
    if process_requested then
      SupervisorClass = ProcessSupervisor
    elseif inline_requested then
      SupervisorClass = InlineSupervisor
    else
      SupervisorClass = Supervisor
    end
    self.supervisor = SupervisorClass.new({
      root = lovr.filesystem.getSource(),
      memory_kb = tonumber(os.getenv("LUANB_KERNEL_MEMORY_KB") or "") or 524288,
      cpu_seconds = tonumber(os.getenv("LUANB_KERNEL_CPU_SECONDS") or "") or 12,
      on_result = on_result,
      on_error = on_error,
    })
  end
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

-- Kernel ids follow notebook objects, not tab indexes.  Closing or reordering a
-- tab therefore leaves every other notebook's persistent kernel attached to the
-- notebook it belongs to.
function App:kernel_id(notebook)
  notebook = notebook or self:notebook()
  if notebook == nil then return nil end
  local id = self.kernel_keys[notebook]
  if id == nil then
    id = "nb" .. self.next_kernel_key
    self.next_kernel_key = self.next_kernel_key + 1
    self.kernel_keys[notebook] = id
  end
  return id
end

function App:close_notebook(index, force)
  index = index or self.active
  local notebook = self.notebooks[index]
  if notebook == nil then return false, "no notebook" end
  if notebook.dirty and not force then return false, "unsaved changes" end
  if self.supervisor and self.supervisor.stop then
    self.supervisor:stop(self:kernel_id(notebook))
  end
  self.kernel_keys[notebook] = nil
  self.closed_notebooks[#self.closed_notebooks + 1] = {
    notebook = notebook, index = index,
  }
  if #self.closed_notebooks > 10 then table.remove(self.closed_notebooks, 1) end
  table.remove(self.notebooks, index)
  for request, target in pairs(self.pending) do
    if target.notebook == index then
      self.pending[request] = nil
    elseif target.notebook > index then
      target.notebook = target.notebook - 1
    end
  end
  if #self.notebooks == 0 then
    self:new_notebook()
  elseif self.active > index then
    self.active = self.active - 1
    if self.ui then self.ui.scroll_to_selected = true end
  elseif self.active == index then
    self.active = math.max(1, math.min(index, #self.notebooks))
    if self.ui then self.ui.scroll_to_selected = true end
  end
  self:save_session()
  self.status = "closed " .. notebook.name
  return true
end

function App:save_and_close(index)
  index = index or self.active
  local notebook = self.notebooks[index]
  if notebook == nil then return false, "no notebook" end
  self:save()
  if notebook.dirty then
    self.status = "save failed; notebook kept open"
    return false, "save failed"
  end
  return self:close_notebook(index, true)
end

function App:reopen_closed_notebook()
  local entry = table.remove(self.closed_notebooks)
  if entry == nil then
    self.status = "no closed notebook to reopen"
    return false
  end
  local notebook = entry.notebook
  self.notebooks[#self.notebooks + 1] = notebook
  self.active = #self.notebooks
  if self.supervisor and self.supervisor.open then
    self.supervisor:open(self:kernel_id(notebook))
  end
  if self.ui then self.ui.scroll_to_selected = true end
  self:save_session()
  self.status = "reopened " .. notebook.name
  return true
end

-- Close every other tab that has no unsaved changes.  Dirty tabs are kept and
-- reported instead of opening one prompt per tab.
function App:close_other_notebooks()
  local keep = self.active
  local closed, kept = 0, 0
  for index = #self.notebooks, 1, -1 do
    if index ~= keep then
      local notebook = self.notebooks[index]
      if notebook.dirty then
        kept = kept + 1
      else
        self:close_notebook(index, true)
        closed = closed + 1
        if index < keep then keep = keep - 1 end
      end
    end
  end
  self.active = keep
  if closed == 0 and kept == 0 then
    self.status = "no other tabs are open"
  elseif kept > 0 then
    self.status = string.format("closed %d clean tab(s); kept %d unsaved",
      closed, kept)
  else
    self.status = string.format("closed %d other tab(s)", closed)
  end
  return closed, kept
end

function App:session_paths()
  local paths, active_path = {}, nil
  for index, notebook in ipairs(self.notebooks) do
    if notebook._path then
      paths[#paths + 1] = notebook._path
      if index == self.active then active_path = notebook._path end
    end
  end
  return paths, active_path
end

function App:save_session()
  if not (lovr and lovr.filesystem) then return end
  local paths, active_path = self:session_paths()
  if #paths == 0 then
    pcall(lovr.filesystem.remove, "session.json")
    return
  end
  pcall(lovr.filesystem.write, "session.json",
    Format.encode_session(paths, active_path))
end

function App:restore_session()
  if not (lovr and lovr.filesystem) then return end
  local text = lovr.filesystem.read("session.json")
  if text == nil then return end
  local paths, active_path = Format.decode_session(text)
  if paths == nil then return end
  for _, path in ipairs(paths) do self:open_path(path) end
  if active_path then
    for index, notebook in ipairs(self.notebooks) do
      if notebook._path == active_path then self:set_tab(index); break end
    end
  end
  if #paths > 0 then self.status = "restored session" end
end

function App:clear_session()
  if lovr and lovr.filesystem then
    pcall(lovr.filesystem.remove, "session.json")
  end
  self.status = "cleared session"
end

function App:set_tab(index)
  if index < 1 or index > #self.notebooks then return end
  self.active = index
  self.scroll = 0
  self.status = self.notebooks[index].name
end

function App:rename_symbol(old_word, new_word)
  local notebook = self:notebook()
  local cell = notebook.cells[notebook.active]
  if cell == nil or old_word == nil or old_word == "" or new_word == "" then
    return
  end
  local source = cell.source
  local line = select(2, source:gsub("\n", ""))
  local last_newline = source:match(".*()\n") or 0
  local character = #source - last_newline
  local uri = "luanb:///notebooks/" .. notebook.name .. "?cell=" .. cell.id
  if self.lsp_ready then
    self.lsp:request("textDocument/rename", {
      textDocument = { uri = uri },
      position = { line = line, character = character },
      newName = new_word,
    }, function(result)
      if result and result.changes then
        local count = LspEdits.apply(notebook, result.changes)
        self.status = "renamed " .. count .. " occurrence(s)"
      else
        self.status = "LSP rename failed"
      end
    end)
  else
    notebook:push_undo()
    local count = require("notebook.editor_text").rename(notebook, old_word,
      new_word)
    self.status = "renamed " .. count .. " occurrence(s) locally"
  end
end

function App:server_diagnostic(cell)
  local uri = "luanb:///notebooks/" .. self:notebook().name .. "?cell=" ..
    tostring(cell.id)
  local items = self.lsp_diagnostics and self.lsp_diagnostics[uri]
  return items and items[1] or nil
end

function App:library_items(filter)
  self.tree_expanded = self.tree_expanded or { notebooks = true }
  local filtering = type(filter) == "string" and filter:match("%S") ~= nil
  local entries = Format.list_tree(self.tree_expanded, "notebooks", 0,
    filtering, self.tree_sort)
  if not filtering then return entries end
  return Format.filter_entries(entries, filter)
end

function App:cycle_tree_sort()
  local modes = { "name", "name-desc", "recent" }
  local next_mode = modes[1]
  for index, mode in ipairs(modes) do
    if mode == self.tree_sort then
      next_mode = modes[index % #modes + 1]
      break
    end
  end
  self.tree_sort = next_mode
  pcall(lovr.filesystem.write, "tree_sort.txt", next_mode)
  self.status = "filetree sort: " .. Format.tree_sort_label(next_mode)
end

function App:new_notebook(folder, requested_name)
  folder = folder or "notebooks"
  local path, name
  if requested_name ~= nil and requested_name:match("%S") then
    path, name = Format.unique_notebook_path(folder, requested_name)
    if path == nil then
      self.status = "create failed: " .. tostring(name)
      return
    end
  else
    local index = 1
    while lovr.filesystem.read(folder .. "/untitled-" .. index .. ".luanb") do
      index = index + 1
    end
    name = "untitled-" .. index .. ".luanb"
    path = folder .. "/" .. name
  end
  local notebook = Notebook.new({
    name = name,
    cells = { { kind = "code", source = "print('new notebook')" } },
  })
  local saved, err = Format.save_in(notebook, folder)
  if saved == nil then
    self.status = "create failed: " .. tostring(err)
    return
  end
  notebook._path = saved
  self.notebooks[#self.notebooks + 1] = notebook
  self.active = #self.notebooks
  self.supervisor:open(self:kernel_id(notebook))
  self.status = "created " .. saved
end

function App:move_notebook(path, folder)
  local target, err = Format.move_path(path, folder)
  if target == nil then
    self.status = "move failed: " .. tostring(err)
    return false
  end
  for _, notebook in ipairs(self.notebooks) do
    if notebook._path == path then notebook._path = target; break end
  end
  self.status = "moved notebook to " .. target
  return true
end

function App:duplicate_notebook()
  local notebook = self:notebook()
  if notebook == nil or notebook._path == nil then
    self.status = "no saved notebook to duplicate"
    return false
  end
  local target, err = Format.duplicate_path(notebook._path)
  if target == nil then
    self.status = "duplicate failed: " .. tostring(err)
    return false
  end
  local duplicate, load_err = Format.load_path(target)
  if duplicate == nil then
    self.status = "duplicate failed: " .. tostring(load_err)
    return false
  end
  duplicate.name = target:match("([^/]+)$")
  self.notebooks[#self.notebooks + 1] = duplicate
  self.active = #self.notebooks
  self.supervisor:open(self:kernel_id(duplicate))
  self.status = "duplicated notebook to " .. target
  return true
end

function App:rename_title(title)
  local changed = self:notebook():set_title(title)
  self.status = changed and "renamed notebook title" or
    "title unchanged or invalid"
  return changed
end

function App:create_folder(name, parent)
  local path, err = Format.create_folder(name, parent)
  if path == nil then self.status = "folder failed: " .. tostring(err); return end
  self.tree_expanded[path] = true
  self.status = "created " .. path
end

function App:rename_folder(path, new_name)
  local new_path, err = Format.rename_folder(path, new_name)
  if new_path == nil then
    self.status = "rename failed: " .. tostring(err)
    return
  end
  local prefix = path .. "/"
  local updates = {}
  for key, value in pairs(self.tree_expanded or {}) do
    if key == path or key:sub(1, #prefix) == prefix then
      updates[#updates + 1] = { key = key, value = value }
    end
  end
  for _, item in ipairs(updates) do
    self.tree_expanded[item.key] = nil
    local suffix = item.key == path and "" or item.key:sub(#path + 1)
    self.tree_expanded[new_path .. suffix] = item.value
  end
  for _, notebook in ipairs(self.notebooks) do
    if notebook._path == path or
       (notebook._path and notebook._path:sub(1, #prefix) == prefix) then
      notebook._path = new_path ..
        (notebook._path == path and "" or notebook._path:sub(#path + 1))
    end
  end
  self.status = "renamed folder to " .. new_path
end

function App:set_folders_expanded(expanded)
  if not expanded then
    self.tree_expanded = {}
    self.status = "collapsed all folders"
    return true
  end
  local entries = Format.list_tree({}, "notebooks", 0, true, self.tree_sort)
  local count = 0
  for _, entry in ipairs(entries) do
    if entry.kind == "directory" then
      self.tree_expanded[entry.path] = true
      count = count + 1
    end
  end
  self.status = "expanded " .. count .. " folder(s)"
  return true
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
    if notebook._path == path then
      self:close_notebook(index, true)
      break
    end
  end
  local prefix = path .. "/"
  for key in pairs(self.tree_expanded or {}) do
    if key == path or key:sub(1, #prefix) == prefix then
      self.tree_expanded[key] = nil
    end
  end
  self.status = "deleted " .. path
end

function App:autosave_tick()
  local notebook = self:notebook()
  if notebook == nil or not notebook.dirty then return end
  local now = lovr.timer.getTime()
  if now - (self.autosave_at or 0) < 20 then return end
  self.autosave_at = now
  local path, err = Format.write_autosave(notebook)
  if path then
    self.status = "autosaved backup"
  elseif err then
    self.status = "autosave failed: " .. tostring(err)
  end
end

function App:recover_autosave()
  local notebook, err = Format.load_autosave(self:notebook())
  if notebook == nil then
    self.status = "no autosave: " .. tostring(err)
    return
  end
  notebook._path = nil
  self.notebooks[#self.notebooks + 1] = notebook
  self.active = #self.notebooks
  self.supervisor:open(self:kernel_id(notebook))
  self.status = "recovered autosave"
end

function App:remember_recent(path)
  if type(path) ~= "string" or path == "" then return end
  local updated = { path }
  for _, value in ipairs(self.recent_paths) do
    if value ~= path and #updated < 10 then updated[#updated + 1] = value end
  end
  self.recent_paths = updated
  pcall(lovr.filesystem.write, "recent.json",
    Format.encode_recent(self.recent_paths))
end

function App:clear_recent()
  self.recent_paths = {}
  pcall(lovr.filesystem.remove, "recent.json")
  self.status = "cleared recent notebooks"
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
  self.supervisor:open(self:kernel_id(notebook))
  self:save_session()
  self:remember_recent(path)
  self.status = "opened " .. notebook.name
end

function App:open_all_kernels()
  for _, notebook in ipairs(self.notebooks) do
    self.supervisor:open(self:kernel_id(notebook))
  end
end

function App:run_next()
  self:run()
  local notebook = self:notebook()
  if notebook.active < #notebook.cells then
    notebook:move(1)
    self.ui.scroll_to_selected = true
    self.status = "running; selected next cell"
  else
    self.status = "running last cell"
  end
end

function App:run_and_insert()
  local notebook = self:notebook()
  local cell = notebook:selected()
  if cell == nil or cell.kind ~= "code" then
    self.status = "markdown cells are not executable"
    return false
  end
  if cell.running then
    self.status = "cell is already running"
    return false
  end
  local index = notebook.active
  self:run()
  if not cell.running then return false end
  notebook:add_cell("code")
  self.ui.scroll_to_selected = true
  self.status = "running cell " .. tostring(index) .. "; inserted cell below"
  return true
end

function App:clear_and_rerun()
  local notebook = self:notebook()
  local cell = notebook:selected()
  if cell == nil or cell.kind ~= "code" then
    self.status = "markdown cells are not executable"
    return false
  end
  if cell.running then
    self.status = "cell is already running"
    return false
  end
  local index = notebook.active
  self:run()
  self.status = "cleared output and rerunning cell " .. tostring(index)
  return true
end

function App:stop_run_all()
  if self._run_all_position == nil then
    self.status = "no run-all queue"
    return false
  end
  self._run_all_position = nil
  self._run_all_stop = nil
  self.status = "stopped run-all queue; the running cell may finish"
  return true
end

function App:restart_and_clear()
  if not self:restart_kernel() then return false end
  self:clear_outputs()
  self.status = "kernel restarted; outputs cleared"
  return true
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
  cell.elapsed = nil
  local cell_token = self.active .. ":" .. index
  local request, err = self.supervisor:run(self:kernel_id(notebook), cell.source,
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
  local elapsed = type(message.elapsed) == "number" and
    Format.duration(message.elapsed) or nil
  local timing = elapsed ~= nil and (" (" .. elapsed .. ")") or ""
  if message.ok == false then
    self.status = "error in " .. cell_label(target.cell) .. timing
  else
    self.status = "finished " .. cell_label(target.cell) .. timing
  end
  if self._run_all_position ~= nil then self:_run_next_all() end
end

function App:widget_event(cell_index, spec, event)
  local cell = self:notebook().cells[cell_index]
  if cell then cell.running = true end
  local cell_token = self.active .. ":" .. cell_index
  local request, err = self.supervisor:widget(self:kernel_id(self:notebook()),
    cell_token,
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

function App:set_ui_scale(scale, persist)
  scale = tonumber(scale) or 1
  self.ui_scale = math.max(0.7, math.min(2, scale))
  if persist ~= false then
    pcall(lovr.filesystem.write, "ui_scale.txt", tostring(self.ui_scale))
  end
  self.status = string.format("UI scale %.0f%%", self.ui_scale * 100)
end

function App:zoom_ui(delta)
  self:set_ui_scale(self.ui_scale + delta)
end

function App:add_cell(kind)
  self:notebook():add_cell(kind or "code")
  self.status = "new " .. (kind or "code") .. " cell below"
end

function App:add_cell_above(kind)
  self:notebook():add_cell_above(kind or "code")
  self.status = "new " .. (kind or "code") .. " cell above"
end

function App:delete_cell()
  local notebook = self:notebook()
  local index = notebook.active
  notebook:delete_cell(index)
  self.status = "deleted cell"
end

function App:set_cell_kind(kind)
  local notebook = self:notebook()
  if notebook:set_cell_kind(notebook.active, kind) then
    self.status = "cell is " .. kind
  end
end

function App:toggle_nvim_default()
  self.nvim_default = not self.nvim_default
  pcall(lovr.filesystem.write, "nvim_default.txt",
    self.nvim_default and "1" or "0")
  self.status = "Neovim for code cells " ..
    (self.nvim_default and "enabled" or "disabled")
end

function App:duplicate_cell()
  self:notebook():duplicate(self:notebook().active)
  self.scroll_to_selected = true
  self.status = "duplicated cell"
end

function App:toggle_markdown_format(prefix, suffix, label)
  local changed = self:notebook():toggle_inline(prefix, suffix, label)
  self.status = changed and ((label or "format") .. " toggled") or
    "markdown cells only"
end

function App:toggle_markdown_block(kind)
  local changed = self:notebook():toggle_block(kind)
  self.status = changed and ("toggled " .. kind .. " line") or
    "markdown cells only"
end

function App:cycle_markdown_heading()
  local changed = self:notebook():cycle_heading()
  self.status = changed and "cycled heading level" or "markdown cells only"
end

function App:insert_markdown_link(url)
  local changed = self:notebook():insert_link(url)
  self.status = changed and "inserted link" or "link needs a URL"
end

function App:toggle_task_item()
  local changed = self:notebook():toggle_task_item()
  self.status = changed and "toggled task item" or "markdown cells only"
end

function App:insert_markdown_block(kind, language)
  local changed = self:notebook():insert_markdown_block(kind, language)
  self.status = changed and ("inserted " .. kind) or "markdown cells only"
end

function App:insert_footnote()
  local changed = self:notebook():insert_footnote()
  self.status = changed and "inserted footnote" or "markdown cells only"
end

function App:toggle_line_comment()
  local changed = self:notebook():toggle_comment()
  self.status = changed and "toggled line comment" or
    "cannot comment this line"
end

function App:shift_current_line(delta)
  local changed = self:notebook():shift_line(delta)
  self.status = changed and (delta < 0 and "moved line up" or "moved line down")
    or "cannot move this line"
end

function App:duplicate_current_line()
  local changed = self:notebook():duplicate_line()
  self.status = changed and "duplicated line" or "cannot duplicate this line"
end

function App:indent_current_line(delta)
  local changed = self:notebook():indent_line(delta)
  self.status = changed and (delta > 0 and "indented line" or "outdented line")
    or "cannot indent this line"
end

function App:move_cell_edge(edge)
  local changed = self:notebook():move_cell_edge(edge)
  self.status = changed and ("moved cell to " .. edge) or "cell is already there"
end

function App:split_cell()
  local changed = self:notebook():split_cell()
  self.status = changed and "split cell at cursor" or "cannot split cell"
end

function App:join_cell_with_next()
  local changed = self:notebook():join_cell_with_next()
  self.status = changed and "joined cell with next" or
    "cannot join cells of different kinds"
end

function App:goto_code_cell(delta)
  local changed = self:notebook():goto_code_cell(delta)
  self.status = changed and ("selected " .. (delta > 0 and "next" or "previous") ..
    " code cell") or "no code cell in that direction"
end

function App:move_cell(delta)
  local notebook = self:notebook()
  local index = notebook.active
  local target = index + delta
  if target < 1 or target > #notebook.cells then return end
  notebook.cells[index], notebook.cells[target] =
    notebook.cells[target], notebook.cells[index]
  notebook:select(target)
  notebook.dirty = true
  self.scroll_to_selected = true
  self.status = "moved cell " .. (delta < 0 and "up" or "down")
end

function App:_run_next_all()
  if self._run_all_position == nil then return end
  local notebook = self:notebook()
  local finish = self._run_all_finished or "all code cells finished"
  local last = self._run_all_stop or #notebook.cells
  for index = self._run_all_position + 1, last do
    if notebook.cells[index].kind == "code" then
      self._run_all_position = index
      notebook:select(index)
      self.scroll_to_selected = true
      self:run()
      return
    end
  end
  self._run_all_position = nil
  local total, timed = Format.total_elapsed(notebook.cells)
  if total ~= nil and timed > 0 then
    self.status = string.format("%s in %s (%d timed)", finish,
      Format.duration(total), timed)
  else
    self.status = finish
  end
end

function App:run_all()
  self._run_all_position = 0
  self._run_all_stop = #self:notebook().cells
  self._run_all_finished = "all code cells finished"
  self.status = "running all code cells"
  self:_run_next_all()
end

-- Run the selected code cell and every code cell after it.  A selected Markdown
-- cell starts at the next code cell, matching the usual "run below" behavior.
function App:run_all_below()
  local notebook = self:notebook()
  local cell = notebook:selected()
  if cell ~= nil and cell.running then
    self.status = "cell is already running"
    return
  end
  self._run_all_position = notebook.active - 1
  self._run_all_stop = #notebook.cells
  self._run_all_finished = "all code cells below finished"
  self.status = "running selected cell and below"
  self:_run_next_all()
end

function App:run_all_above()
  local notebook = self:notebook()
  local cell = notebook:selected()
  if cell ~= nil and cell.running then
    self.status = "cell is already running"
    return
  end
  self._run_all_position = 0
  self._run_all_stop = notebook.active
  self._run_all_finished = "all code cells above finished"
  self.status = "running selected cell and above"
  self:_run_next_all()
end

function App:export_html()
  local notebook = self:notebook()
  local safe = notebook.name:gsub("[^%w_.-]", "_"):gsub("%.luanb$", "")
  local path = "exports/" .. safe .. ".html"
  pcall(lovr.filesystem.createDirectory, "exports")
  local ok, err = pcall(lovr.filesystem.write, path,
    require("notebook.format").to_html(notebook,
      require("notebook.format").backlinks(self.notebooks, notebook:title())))
  self.status = ok and ("exported " .. path) or ("export failed: " ..
    tostring(err))
end

function App:export_markdown()
  local notebook = self:notebook()
  local safe = notebook.name:gsub("[^%w_.-]", "_")
  local path = "exports/" .. safe:gsub("%.luanb$", "") .. ".md"
  pcall(lovr.filesystem.createDirectory, "exports")
  local ok, err = pcall(lovr.filesystem.write, path,
    require("notebook.format").to_markdown(notebook))
  self.status = ok and ("exported " .. path) or ("export failed: " ..
    tostring(err))
end

function App:clear_outputs()
  self._run_all_position = nil
  for _, cell in ipairs(self:notebook().cells) do
    cell.output = ""
    cell.scene = nil
    cell.widgets = {}
    cell.error = nil
    cell.running = false
  end
  self.status = "cleared outputs"
end

function App:set_outputs_expanded(expanded)
  local changed = self:notebook():set_outputs_expanded(expanded)
  self.status = changed and
    (expanded and "expanded all long outputs" or "collapsed all long outputs") or
    (expanded and "no long outputs to expand" or "no long outputs to collapse")
end

function App:clear_cell_output()
  local notebook = self:notebook()
  local cell = notebook and notebook:selected()
  if cell == nil then
    self.status = "no cell to clear"
    return false
  end
  if cell.running then
    self.status = "cell is still running"
    return false
  end
  cell.output = ""
  cell.scene = nil
  cell.widgets = {}
  cell.error = nil
  cell.output_expanded = false
  self.status = "cleared output of cell " .. tostring(notebook.active)
  return true
end

function App:restart_notebook(notebook, index)
  if not self.supervisor.restart then return false end
  self.supervisor:restart(self:kernel_id(notebook))
  for request, target in pairs(self.pending) do
    if target.notebook == index then self.pending[request] = nil end
  end
  for _, cell in ipairs(notebook.cells) do cell.running = false end
  return true
end

function App:restart_kernel()
  self._run_all_position = nil
  if self:restart_notebook(self:notebook(), self.active) then
    self.status = "kernel restarted"
    return true
  end
  self.status = "kernel restart is unavailable for this backend"
  return false
end

function App:restart_all_kernels()
  self._run_all_position = nil
  local count = 0
  for index, notebook in ipairs(self.notebooks) do
    if self:restart_notebook(notebook, index) then count = count + 1 end
  end
  if count == 0 then
    self.status = "kernel restart is unavailable for this backend"
    return false
  end
  self.pending = {}
  self.status = string.format("restarted %d kernel(s)", count)
  return true
end

-- Restart first, then run every code cell in the restarted state.  The restart
-- is synchronous for every backend, so the first job always sees the new kernel.
function App:restart_and_run_all()
  if self:restart_kernel() then self:run_all() end
end

function App:copy_cell_source()
  local notebook = self:notebook()
  local cell = notebook and notebook:selected()
  if cell == nil then
    self.status = "no cell to copy"
    return false
  end
  local ok = pcall(function()
    lovr.system.setClipboardText(cell.source or "")
  end)
  if ok then
    self.status = "copied source of cell " .. tostring(notebook.active)
  else
    self.status = "clipboard is unavailable"
  end
  return ok
end

-- Copy captured text output, or the error text when the cell failed.  Scene
-- descriptions and widget state are live values, not clipboard text.
function App:copy_cell_output()
  local notebook = self:notebook()
  local cell = notebook and notebook:selected()
  if cell == nil then
    self.status = "no cell to copy"
    return false
  end
  local text = cell.output
  local kind = "output"
  if text == nil or text == "" then
    text = cell.error
    kind = "error"
  end
  if text == nil or text == "" then
    self.status = "cell " .. tostring(notebook.active) .. " has no text output"
    return false
  end
  local ok = pcall(function()
    lovr.system.setClipboardText(text)
  end)
  if ok then
    self.status = "copied " .. kind .. " of cell " .. tostring(notebook.active)
  else
    self.status = "clipboard is unavailable"
  end
  return ok
end

function App:goto_heading(delta)
  local notebook = self:notebook()
  local target = notebook:heading_relative(delta)
  if target == nil then
    self.status = delta > 0 and "no later heading" or "no earlier heading"
    return false
  end
  notebook:select(target)
  self.scroll_to_selected = true
  local heading = notebook.cells[target].source:gsub("^#+%s*", ""):gsub("\n.*$", "")
  self.status = "heading: " .. heading
  return true
end

function App:set_headings_collapsed(collapsed)
  local changed = self:notebook():set_headings_collapsed(collapsed)
  if changed then
    self.scroll_to_selected = true
    self.status = collapsed and "collapsed all headings" or "expanded all headings"
  else
    self.status = collapsed and "all headings are already collapsed" or
      "all headings are already expanded"
  end
  return changed
end

function App:open_title(title)
  for index, notebook in ipairs(self.notebooks) do
    if notebook:title() == title or notebook.name == title or
       notebook.name == title .. ".luanb" then
      self:set_tab(index)
      self.status = "opened " .. title
      return true
    end
  end
  self.status = "no notebook named " .. tostring(title)
  return false
end

function App:leave_inline_nvim()
  if not self.nvim_inline then return end
  self._nvim_hidden_cell = self:notebook():selected()
  self._nvim_pending_hide = self.nvim_session ~= nil
  self.show_nvim = false
  self.nvim_inline = false
  self.nvim_inline_original = nil
  self._nvim_undo_started = false
  self._nvim_sync_at = 0
  if self.ui then
    self.ui.vim_scope = "notebook"
    self.ui.vim_normal = true
    self.ui.vim_pending = nil
    self.ui.vim_text_object = nil
    self.ui.vim_pending_mark = nil
    self.ui.vim_pending_register = false
    self.ui.vim_command = nil
    self.ui.vim_search = nil
  end
  self.status = "left cell; edits applied live"
end

function App:sync_hidden_nvim()
  if not self._nvim_pending_hide then return end
  self._nvim_pending_hide = false
  local cell = self._nvim_hidden_cell
  self._nvim_hidden_cell = nil
  if cell == nil or self.nvim_session == nil or self.nvim_session.exited then
    return
  end
  local lines = self.nvim_session:get_lines(0.2)
  if lines == nil then return end
  local source = table.concat(lines, "\n")
  if source ~= cell.source then
    cell.source = source
    self:notebook().dirty = true
  end
end

function App:sync_inline_nvim()
  if not self.show_nvim or not self.nvim_inline or
     self.nvim_session == nil or self.nvim_session.exited then return end
  local now = lovr.timer.getTime()
  if now - (self._nvim_sync_at or 0) < 0.03 then return end
  self._nvim_sync_at = now
  local lines = self.nvim_session:get_lines()
  if lines == nil then return end
  local source = table.concat(lines, "\n")
  local cell = self:notebook():selected()
  if cell == nil then return end
  if source ~= cell.source then
    if not self._nvim_undo_started then
      self:notebook():push_undo("Neovim edit")
      self._nvim_undo_started = true
    end
    cell.source = source
    self:notebook().dirty = true
  end
  local cursor = self.nvim_session:request("nvim_win_get_cursor", { 0 })
  if type(cursor) == "table" and cursor[1] then
    local row = math.max(1, cursor[1])
    local col = math.max(0, cursor[2] or 0)
    local start = 1
    for _ = 1, row - 1 do
      local newline = source:find("\n", start, true)
      if newline == nil then break end
      start = newline + 1
    end
    cell.cursor = math.max(1, math.min(start + col, #source + 1))
  end
  if self.ui then
    self.ui.vim_scope = "cell"
    self.ui.vim_normal = self.nvim_session.grid.mode ~= "insert"
  end
end

function App:open_nvim()
  local cell = self:notebook():selected()
  if cell.kind ~= "code" and cell.kind ~= "markdown" then
    self.status = "Neovim editor is for code and markdown cells"
    return
  end
  self.nvim_inline_original = cell.source
  self._nvim_undo_started = false
  self._nvim_sync_at = 0
  self._nvim_pending_hide = false
  self._nvim_hidden_cell = nil
  self.nvim_delete_prompt = nil
  if self.ui then
    self.ui.vim_scope = "cell"
    self.ui.vim_normal = true
  end
  if self.nvim_session then
    self.nvim_session:input("<Esc>")
    self.nvim_session:update()
    local lines = {}
    for source_line in ((cell.source or "") .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = source_line
    end
    local loaded, load_error = self:load_nvim_buffer(lines,
      cell.kind == "markdown" and "markdown" or "lua", false)
    if not loaded then
      self:close_nvim(false)
      self.status = "Neovim reload failed: " .. tostring(load_error)
      return self:open_nvim()
    end
    self.show_nvim, self.nvim_notebook, self.nvim_inline = true, false, true
    self.status = "Neovim normal mode: i inserts, F10 applies"
    return
  end
  local path = os.tmpname() .. (cell.kind == "markdown" and ".md" or ".lua")
  local handle = io.open(path, "wb")
  if handle == nil then self.status = "cannot create nvim buffer"; return end
  handle:write(cell.source or "")
  handle:close()
  os.execute("chmod 600 '" .. path .. "'")
  local ok, session = pcall(require("notebook.nvim.session").new, {
    cols = 100, rows = 30, file = path,
    background = require("ui.theme").mode,
    clean = os.getenv("LUANB_NVIM_CLEAN") ~= "0",
  })
  if not ok then
    os.remove(path)
    self.status = "nvim failed: " .. tostring(session)
    return
  end
  local ready = pcall(function()
    for _ = 1, 150 do
      session:update()
      if session.grid:line(0):find("%S") then break end
      os.execute("sleep 0.02")
    end
    session:input("<Esc>")
    for _ = 1, 5 do session:update(); os.execute("sleep 0.01") end
  end)
  if not ready then
    pcall(function() session:close() end)
    os.remove(path)
    self.status = "nvim failed to become ready"
    return
  end
  local view_ok, view = pcall(require("ui.nvim").new, session,
    self.nvim_font or self.font)
  if not view_ok then
    pcall(function() session:close() end)
    os.remove(path)
    self.status = "nvim view failed: " .. tostring(view)
    return
  end
  self.nvim_session = session
  self.nvim_view = view
  self.nvim_path = path
  self.show_nvim = true
  self.nvim_inline = true
  self.status = "Neovim normal mode: i inserts, F10 applies"
end

function App:load_nvim_buffer(lines, filetype, insert, cursor_row)
  local session = self.nvim_session
  if session == nil then return false end
  pcall(function()
    session:input("<Esc>")
    session:update()
  end)
  session:command("enew!")
  local ok, err = session:set_lines(lines, cursor_row or 1)
  if not ok then return nil, err end
  session:command("set filetype=" .. filetype)
  -- A reused buffer should not carry the previous cell's undo history.
  session:command("set undolevels=-1")
  session:command("set undolevels=1000")
  if insert ~= false then session:input("i") end
  return true
end

function App:close_nvim(save, keep, options)
  if self.nvim_session == nil then return end
  options = options or {}
  local was_inline = self.nvim_inline
  local original = self.nvim_inline_original
  local session = self.nvim_session
  local cursor_row, cursor_col = 0, 0
  if session.grid then
    cursor_row = math.max(0, session.grid.cursor.row or 0)
    cursor_col = math.max(0, session.grid.cursor.col or 0)
  end
  if not save and was_inline and original ~= nil then
    local cell = self:notebook():selected()
    if cell then
      cell.source = original
      cell.cursor = math.max(1, math.min(cell.cursor or 1, #original + 1))
      self:notebook().dirty = true
    end
  end
  local lines
  if save then
    -- Flush typeahead before reading the buffer.
    pcall(function()
      session:input("<Esc>")
      session:update()
    end)
    local ok, value, err = pcall(function() return session:get_lines() end)
    if not ok then
      self.status = "Neovim save failed: " .. tostring(value)
      return false
    end
    lines = value
    if lines == nil or #lines == 0 then
      self.status = "Neovim save failed: " .. tostring(err or "empty buffer")
      return false
    end
    local cursor_ok, cursor = pcall(function()
      return session:request("nvim_win_get_cursor", { 0 })
    end)
    if cursor_ok and type(cursor) == "table" then
      cursor_row = math.max(0, (cursor[1] or 1) - 1)
      cursor_col = math.max(0, cursor[2] or cursor_col)
    end
  end

  local applied = false
  if save and lines then
    if self.nvim_notebook then
      local notebook = self:notebook()
      local plan, plan_error = NvimBuffer.plan(notebook.cells, lines)
      if plan == nil then
        self.status = "Neovim save failed: " .. tostring(plan_error)
        return false
      end
      if #plan.missing > 0 and not options.delete_missing then
        self.nvim_delete_prompt = {
          missing = plan.missing,
          old_count = plan.old_count,
          previews = NvimBuffer.missing_previews(notebook.cells,
            plan.missing, 58),
        }
        self.status = string.format(
          "Neovim markers omit %d cell(s); Enter/y deletes, Esc/n cancels",
          #plan.missing)
        return false
      end
      local summary, apply_error = NvimBuffer.apply(notebook, plan, {
        delete_missing = options.delete_missing,
        label = "Neovim notebook edit",
      })
      if summary == nil then
        self.status = "Neovim save failed: " .. tostring(apply_error)
        return false
      end
      self.nvim_delete_prompt = nil
      applied = true
      if summary.deleted > 0 then
        self.status = string.format(
          "deleted %d Neovim cell(s); F6 writes the file", summary.deleted)
      elseif summary.added > 0 then
        self.status = "added " .. summary.added ..
          " Neovim cell(s); F6 writes the file"
      elseif summary.changed then
        self.status = "applied Neovim changes; F6 writes the file"
      else
        self.status = "no Neovim changes; F6 writes the file"
      end
    else
      local source = table.concat(lines, "\n")
      local cell = self:notebook():selected()
      if cell.source ~= source then
        self:notebook():push_undo("Neovim edit")
        cell.source = source
        self:notebook().dirty = true
      end
      local line_start = 1
      for _ = 1, cursor_row do
        local newline = source:find("\n", line_start, true)
        if newline == nil then break end
        line_start = newline + 1
      end
      cell.cursor = math.max(1, math.min(line_start + cursor_col,
        #source + 1))
      applied = true
      self.status = "applied Neovim changes; F6 writes the file"
    end
  end

  if not keep then
    pcall(function() session:close() end)
    if self.nvim_path then os.remove(self.nvim_path); self.nvim_path = nil end
    self.nvim_session, self.nvim_view = nil, nil
  end
  self.show_nvim = false
  if save and not applied then self.status = "Neovim discarded" end
  self.nvim_notebook = false
  self.nvim_inline = false
  self.nvim_inline_original = nil
  self.nvim_delete_prompt = nil
  self._nvim_undo_started = false
  self._nvim_sync_at = 0
  self._nvim_pending_hide = false
  self._nvim_hidden_cell = nil
  self.nvim_cells = {}
  self.nvim_cell_rows = {}
  if self.ui then
    self.ui.vim_scope = "notebook"
    self.ui.vim_normal = true
    self.ui.vim_pending = nil
    self.ui.vim_text_object = nil
    self.ui.vim_pending_mark = nil
    self.ui.vim_pending_register = false
    self.ui.vim_command = nil
    self.ui.vim_search = nil
  end
  return true
end

function App:hide_nvim(save, options)
  return self:close_nvim(save, true, options)
end

function App:confirm_nvim_deletion()
  if self.nvim_delete_prompt == nil then return false end
  self.nvim_delete_prompt = nil
  return self:hide_nvim(true, { delete_missing = true })
end

function App:cancel_nvim_deletion()
  if self.nvim_delete_prompt == nil then return false end
  self.nvim_delete_prompt = nil
  self.status = "Neovim save cancelled; buffer kept"
  return true
end

function App:notebook_cell_at_cursor()
  local index = self:notebook().active
  if self.nvim_session == nil then return index end
  local row = (self.nvim_session.grid.cursor.row or 0) + 1
  pcall(function()
    self.nvim_session:input("<Esc>")
    self.nvim_session:update()
    local cursor = self.nvim_session:request("nvim_win_get_cursor", { 0 })
    if type(cursor) == "table" and cursor[1] then
      row = cursor[1] + 1
    end
  end)
  for _, entry in ipairs(self.nvim_cell_rows or {}) do
    if entry.row <= row then index = entry.index end
  end
  return index
end

function App:run_nvim_cell()
  if self.nvim_session == nil then return end
  local index = self:notebook_cell_at_cursor()
  if self:hide_nvim(true) == false then return end
  self:notebook():select(index)
  self.scroll_to_selected = true
  if self:notebook():selected().kind == "code" then
    self:run()
  else
    self.status = "markdown cell selected; not executed"
  end
end

function App:open_nvim_notebook()
  local notebook = self:notebook()
  self.nvim_delete_prompt = nil
  local lines, rows = NvimBuffer.encode(notebook.cells)
  local cells = {}
  for _, entry in ipairs(rows) do cells[entry.index] = true end
  if #lines == 0 then self.status = "notebook has no code cells"; return end
  if self.nvim_session then
    self.nvim_session:input("<Esc>")
    self.nvim_session:update()
    local target_row = 1
    for _, entry in ipairs(rows) do
      if entry.index == notebook.active then target_row = entry.row + 1 end
    end
    local loaded, load_error = self:load_nvim_buffer(lines, "lua", false,
      target_row)
    if not loaded then
      self:close_nvim(false)
      self.status = "Neovim reload failed: " .. tostring(load_error)
      return self:open_nvim_notebook()
    end
    self.nvim_cells, self.nvim_cell_rows = cells, rows
    self.show_nvim, self.nvim_notebook, self.nvim_inline = true, true, false
    self.status = "Neovim notebook (warm): F10 save, F5 run"
    return
  end
  local path = os.tmpname() .. ".lua"
  local handle = io.open(path, "wb")
  if handle == nil then self.status = "cannot create notebook buffer"; return end
  handle:write(table.concat(lines, "\n"))
  handle:close()
  os.execute("chmod 600 '" .. path .. "'")
  local ok, session = pcall(require("notebook.nvim.session").new, {
    cols = 100, rows = 30, file = path,
    background = require("ui.theme").mode,
    clean = os.getenv("LUANB_NVIM_CLEAN") ~= "0",
  })
  if not ok then
    os.remove(path); self.status = "nvim failed: " .. tostring(session); return
  end
  local target_row = 1
  for _, entry in ipairs(rows) do
    if entry.index == notebook.active then target_row = entry.row + 1 end
  end
  local ready = pcall(function()
    for _ = 1, 150 do
      session:update()
      if session.grid:line(0):find("%S") then break end
      os.execute("sleep 0.02")
    end
    session:request("nvim_win_set_cursor", { 0, { target_row, 0 } })
  end)
  if not ready then
    pcall(function() session:close() end)
    os.remove(path)
    self.status = "nvim failed to become ready"
    return
  end
  local view_ok, view = pcall(require("ui.nvim").new, session,
    self.nvim_font or self.font)
  if not view_ok then
    pcall(function() session:close() end)
    os.remove(path)
    self.status = "nvim view failed: " .. tostring(view)
    return
  end
  self.nvim_session, self.nvim_cells = session, cells
  self.nvim_cell_rows = rows
  self.nvim_view = view
  self.nvim_path, self.nvim_notebook, self.show_nvim = path, true, true
  self.nvim_inline = false
  self.status = "Neovim notebook (normal mode): i to edit, F10 save, F5 run"
end

function App:save_notebook(notebook)
  local ok, path, absolute
  if notebook._path and not notebook._path:match("^notebooks/") then
    ok, path = pcall(Format.save_path, notebook, notebook._path)
    absolute = path
  else
    ok, path, absolute = pcall(Format.save, notebook)
  end
  if not ok or path == nil then
    return false, tostring(path or absolute or "write failed")
  end
  notebook.dirty = false
  Format.remove_autosave(notebook)
  return true, absolute or path
end

function App:save()
  local ok, path = self:save_notebook(self:notebook())
  self.status = ok and ("saved " .. tostring(path)) or
    ("save failed: " .. tostring(path))
end

function App:save_all()
  local saved, failed = 0, 0
  local last_path
  for _, notebook in ipairs(self.notebooks) do
    if notebook.dirty then
      local ok, path = self:save_notebook(notebook)
      if ok then
        saved = saved + 1
        last_path = path
      else
        failed = failed + 1
      end
    end
  end
  if saved == 0 and failed == 0 then
    self.status = "no unsaved notebooks"
  elseif failed > 0 then
    self.status = string.format("saved %d notebook(s); %d failed", saved,
      failed)
  else
    self.status = string.format("saved %d notebook(s) (%s)", saved,
      tostring(last_path))
  end
end

function App:save_as()
  local dialog = require("notebook.native_dialog")
  local target, err = dialog.save(self:notebook().name .. ".luanb")
  if target == nil then
    self.status = "save as: " .. tostring(err)
    return
  end
  local ok, saved = pcall(Format.save_path, self:notebook(), target)
  self.status = ok and ("saved " .. tostring(saved)) or
    ("save as failed: " .. tostring(saved))
end

function App:open_dialog()
  local dialog = require("notebook.native_dialog")
  local target, err = dialog.open()
  if target == nil then
    self.status = "open: " .. tostring(err)
    return
  end
  self:open_path(target)
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
  local old = self:notebook()
  if self.supervisor and self.supervisor.stop then
    self.supervisor:stop(self:kernel_id(old))
  end
  self.kernel_keys[old] = nil
  loaded._path = old._path
  self.notebooks[self.active] = loaded
  self.supervisor:open(self:kernel_id(loaded))
  self.scroll = 0
  self.status = "loaded " .. loaded.name
end

function App:update()
  if self.show_nvim then
    if self.nvim_view then self.nvim_view:update() end
    if self.nvim_inline then self:sync_inline_nvim() end
    if self.nvim_session and self.nvim_session.exited then
      self:close_nvim(false)
      self.status = "Neovim exited unexpectedly"
    end
  elseif self.ui then
    self.ui:update()
  end
  self.supervisor:poll()
  if not self.show_nvim then self:sync_hidden_nvim() end
  self:autosave_tick()
  if self.screenshot_readback and self.screenshot_readback:isComplete() then
    local image = self.screenshot_readback:getImage()
    self.screenshot_readback = nil
    if image and image:getFormat() == "rgba8" then
      local blob = image:encode()
      lovr.filesystem.createDirectory("screenshots")
      local path = "screenshots/notebook-" .. tostring(os.time()) .. ".png"
      lovr.filesystem.write(path, blob:getString())
      self.last_screenshot = path
      self.status = "screenshot " .. path
      print("SCREENSHOT=" .. path)
      if self.qa_screenshot then lovr.event.quit() end
    end
  end
  if self.qa_screenshot and not self.screenshot_requested and
     not self.screenshot_readback and
     lovr.timer.getTime() > (self.qa_screenshot_after or 3) then
    local cell = self:notebook().cells[self:notebook().active]
    if cell == nil or not cell.running then self.screenshot_requested = true end
  end
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
  local active_cell = self:notebook().cells[self:notebook().active]
  if self.qa_screenshot and not self.screenshot_requested and
     not self.screenshot_readback and
     lovr.timer.getTime() > (self.qa_screenshot_after or 3) and
     (active_cell == nil or not active_cell.running) then
    self.screenshot_requested = true
  end
  if os.getenv("LUANB_LSP_SMOKE") and self.lsp_ready and
     not self.lsp_smoke_done then
    self.lsp_smoke_done = true
    print("SMOKE_LSP=ready")
    lovr.event.quit()
  end
  if self.lsp and self.lsp_out then
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
        self.supervisor:restart(self:kernel_id(notebook))
        self.status = "kernel restarted after timeout in " .. cell_label(target.cell)
      else
        self.status = "kernel timeout in " .. cell_label(target.cell)
      end
    end
  end
end

function lovr.load()
  local app = App:new(Notebook.demo())
  local target_paths = {}
  if arg then
    for _, value in ipairs(arg) do
      if type(value) == "string" and not value:match("^%-") and
          value:match("%.luanb$") then
        target_paths[#target_paths + 1] = value
      end
    end
  end
  app.font = lovr.graphics.newFont(18)
  local nvim_font_ok, nvim_font = pcall(lovr.graphics.newFont,
    "assets/DejaVuSansMono.ttf", 18)
  app.nvim_font = nvim_font_ok and nvim_font or app.font
  app.font:setPixelDensity(1)
  app.title_font = lovr.graphics.newFont(22)
  app.math_font = lovr.graphics.newFont("assets/DejaVuSans.ttf", 18)
  app.math_font:setPixelDensity(1)
  app.math_bold = lovr.graphics.newFont("assets/DejaVuSans-Bold.ttf", 18)
  app.math_bold:setPixelDensity(1)
  app.math_italic = lovr.graphics.newFont("assets/DejaVuSans-Oblique.ttf", 18)
  app.math_italic:setPixelDensity(1)
  app.title_font:setPixelDensity(1)
  app.ui = UI.new(app)
  Theme.load()
  local nvim_ok, nvim_default = pcall(lovr.filesystem.read, "nvim_default.txt")
  if nvim_ok and nvim_default then
    app.nvim_default = nvim_default:find("1") ~= nil
  else
    local ok, NvimSession = pcall(require, "notebook.nvim.session")
    app.nvim_default = ok and NvimSession.available("nvim")
  end
  if os.getenv("LUANB_QA_THEME") then Theme.set(os.getenv("LUANB_QA_THEME")) end
  if os.getenv("LUANB_QA_HELP") then app.ui.show_help = true end
  if os.getenv("LUANB_QA_CELL_SCOPE") then
    app.ui.vim_scope = os.getenv("LUANB_QA_LASTJ") == "notebook" and "notebook" or "cell"
    app.ui.vim_normal = true
  end
  if os.getenv("LUANB_QA_UI_SCALE") then
    app:set_ui_scale(tonumber(os.getenv("LUANB_QA_UI_SCALE")), false)
  end
  if os.getenv("LUANB_QA_PALETTE") then app.ui.show_palette = true end
  if os.getenv("LUANB_QA_OUTLINE") then app.ui.show_outline = true end
  if os.getenv("LUANB_QA_TAGS") then app.ui.show_tags = true end
  if os.getenv("LUANB_QA_TIMING") then app.ui.show_timing = true end
  if os.getenv("LUANB_QA_STATS") then app.ui:open_stats() end
  if os.getenv("LUANB_QA_OUTPUT") then
    local target = tonumber(os.getenv("LUANB_QA_CELL") or "") or
      app:notebook().active
    local cell = app:notebook().cells[target] or app:notebook():selected()
    local lines = {}
    for index = 1, 12 do
      lines[index] = string.format("QA output line %02d", index)
    end
    cell.output = table.concat(lines, "\n")
    cell.output_expanded = os.getenv("LUANB_QA_OUTPUT") == "expanded"
  end
  if os.getenv("LUANB_QA_HISTORY") then
    local notebook = app:notebook()
    notebook.cells[notebook.active].source = ""
    notebook.cells[notebook.active].cursor = 1
    notebook:reset_history()
    notebook:insert("a")
    notebook:undo()
    notebook:insert("b")
    notebook:flush_history()
    app.ui:open_history()
  end
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
  for _, target_path in ipairs(target_paths) do
    app:open_path(target_path)
  end
  if #target_paths == 0 then app:restore_session() end
  if Runtime.has_native_filesystem() then lovr.filesystem.watch() end
  _G.app = app
  if os.getenv("LUANB_SMOKE_ZOOM") then
    app:set_ui_scale(1.2, false)
    local increased = app.ui_scale
    app:set_ui_scale(0.8, false)
    local decreased = app.ui_scale
    app:set_ui_scale(1, false)
    print("SMOKE_ZOOM=" .. increased .. ":" .. decreased .. ":" ..
      app.ui_scale)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_SCOPE") then
    local notebook = app:notebook()
    app.ui.vim_scope = "notebook"
    app.ui.vim_normal = true
    app.ui:keypressed("j")
    local cell_after_j = notebook.active
    app.ui:keypressed("i")
    local after_i = app.ui.vim_scope
    app.ui:keypressed("i")
    local after_ii = app.ui.vim_scope .. ":" .. tostring(app.ui.vim_normal)
    app.ui:keypressed("escape")
    local after_escape = app.ui.vim_scope
    app.ui:keypressed("escape")
    local after_escape2 = app.ui.vim_scope
    print("SMOKE_SCOPE=" .. cell_after_j .. ":" .. after_i .. ":" ..
      after_ii .. ":" .. after_escape .. ":" .. after_escape2)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_PRUN") then
    app:notebook():select(2)
    app.ui.vim_normal = true
    app.ui.focused_output_cell = 2
    app.ui:keypressed("p")
    print("SMOKE_PRUN=" .. tostring(app:notebook().cells[2].running) .. ":" ..
      tostring(app:notebook().active) .. ":" ..
      tostring(app.ui.vim_normal) .. ":" ..
      tostring(app.ui.focused_output_cell == 2))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_PRUNNEXT") then
    app:notebook():select(2)
    app:run_next()
    print("SMOKE_PRUNNEXT=" .. tostring(app:notebook().active))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_CELLKEYS") then
    app.ui.vim_scope = "notebook"
    app.ui.vim_normal = true
    app:notebook():select(2)
    app.ui:keypressed("b")
    local below = app:notebook().active
    app.ui:keypressed("a")
    local above = app:notebook().active
    app.ui:keypressed("M")
    local markdown = app:notebook():selected().kind
    print("SMOKE_CELLKEYS=" .. below .. ":" .. above .. ":" .. markdown)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_HELP") then
    app.ui.vim_normal = true
    app.ui:keypressed("?")
    print("SMOKE_HELP=" .. tostring(app.ui.show_help))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_STATS") then
    app.ui:open_stats()
    local values = app.ui.stats.values
    app.ui:keypressed("escape")
    print("SMOKE_STATS=" .. values.cells .. ":" .. values.lines .. ":" ..
      tostring(app.ui.show_stats))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_GLOBAL_FIND") then
    app.ui:open_global_find()
    app.ui:textinput("Second kernel")
    local target
    for _, result in ipairs(app.ui.global_find_results) do
      if result.notebook == 2 then target = result; break end
    end
    local total = app.ui.global_find_total
    if target then app.ui:open_global_result(target) end
    print(string.format("SMOKE_GLOBAL_FIND=%s:%d:%d:%s:%s",
      tostring(target ~= nil), total, app.active,
      tostring(not app.ui.show_global_find),
      tostring(app:notebook().cells[app:notebook().active] ~= nil)))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_CLOSE") then
    local before = #app.notebooks
    local first = app:notebook()
    local old_id = app:kernel_id(first)
    first.dirty = true
    app.ui:request_close()
    local prompted = app.ui.close_prompt ~= nil
    app.ui.close_prompt = nil
    local guarded = app:close_notebook(app.active)
    local closed = app:close_notebook(app.active, true)
    local remaining = app:notebook()
    local kernel_ok = app.supervisor.kernels[app:kernel_id(remaining)] ~= nil
    local old_gone = app.supervisor.kernels[old_id] == nil
    app.ui:keypressed("t", { ctrl = true, alt = true })
    local reopened = #app.notebooks == before and
      app:notebook().name == first.name
    local reopen_kernel =
      app.supervisor.kernels[app:kernel_id(app:notebook())] ~= nil
    local after_reopen = #app.notebooks
    local other_before = after_reopen
    local closed_others, kept_others = app:close_other_notebooks()
    local others_ok = closed_others == other_before - 1 and kept_others == 0
    print(string.format("SMOKE_CLOSE=%d:%d:%s:%s:%s:%s:%s:%s:%s:%s:%s:%d", before,
      after_reopen, tostring(prompted), tostring(guarded),
      tostring(closed), tostring(kernel_ok), tostring(old_gone),
      tostring(reopened), tostring(reopen_kernel), tostring(others_ok),
      tostring(kept_others), closed_others))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_OUTPUT") then
    local cell = app:notebook():selected()
    local lines = {}
    for index = 1, 12 do lines[index] = "line " .. index end
    cell.output = table.concat(lines, "\n")
    local shown, total = Notebook.output_lines_shown(cell)
    local expanded = app:notebook():toggle_output(app:notebook().active)
    local expanded_shown = Notebook.output_lines_shown(cell)
    print("SMOKE_OUTPUT=" .. shown .. ":" .. total .. ":" ..
      tostring(expanded) .. ":" .. expanded_shown)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_FKEYS") then
    app.ui:keypressed("f1")
    local palette = app.ui.show_palette
    app.ui:keypressed("f1")
    app.ui:keypressed("f2")
    local tree = app.ui.show_tree
    app.ui:keypressed("f2")
    app.ui:keypressed("f3")
    local vim = app.vim_mode
    app.ui:keypressed("f3")
    app.ui:keypressed("f4")
    local zen = app.ui.zen_mode
    app.ui:keypressed("f4")
    app.ui:keypressed("f10")
    local extensions = app.ui.show_extensions
    app.ui:keypressed("f10")
    app.ui:keypressed("f11")
    local outline = app.ui.show_outline
    app.ui:keypressed("f11")
    app.ui:keypressed("f12")
    local help = app.ui.show_help
    print("SMOKE_FKEYS=" .. tostring(palette) .. ":" .. tostring(tree) ..
      ":" .. tostring(not vim) .. ":" .. tostring(zen) .. ":" ..
      tostring(extensions) .. ":" .. tostring(outline) .. ":" ..
      tostring(help))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_GUNDO") then
    local notebook = app:notebook()
    notebook.cells[1].source = ""
    notebook.cells[1].cursor = 1
    notebook:reset_history()
    notebook:insert("a")
    app.ui.vim_normal = true
    app.ui:keypressed("g")
    app.ui:keypressed("-")
    local undone = notebook.cells[1].source
    app.ui:keypressed("g")
    app.ui:keypressed("+")
    print("SMOKE_GUNDO=" .. tostring(undone == "") .. ":" ..
      notebook.cells[1].source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_TYPECOMP") then
    local cell = app:notebook():selected()
    cell.source = 'local config = { name = "x", count = 1 }\nconfig.'
    cell.cursor = #cell.source + 1
    app.ui:open_completion()
    local items = app.ui.completion and app.ui.completion.items or {}
    table.sort(items)
    print("SMOKE_TYPECOMP=" .. table.concat(items, ","))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_UNDOTREE") then
    app:notebook().cells[1].source = ""
    app:notebook().cells[1].cursor = 1
    app:notebook():reset_history()
    app:notebook():insert("a")
    app:notebook():undo()
    app:notebook():insert("b")
    app:notebook():flush_history()
    local nodes = app:notebook():history_nodes_flat()
    app:notebook():undo()
    app:notebook():redo()
    print("SMOKE_UNDOTREE=" .. #nodes .. ":" ..
      app:notebook():selected().source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMOBJ") then
    app.ui.vim_normal = true
    local cell = app:notebook():selected()
    cell.source = 'print("hello")'
    cell.cursor = 8
    app.ui:keypressed("d")
    app.ui:keypressed("i")
    app.ui:keypressed('"')
    print("SMOKE_VIMOBJ=" .. cell.source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_CELLOPS") then
    app:notebook():select(2)
    app:add_cell("markdown")
    local markdown = app:notebook():selected().kind
    app:set_cell_kind("code")
    local code = app:notebook():selected().kind
    app:add_cell_above("markdown")
    local above = app:notebook().cells[2].kind
    app:delete_cell()
    print("SMOKE_CELLOPS=" .. markdown .. ":" .. code .. ":" .. above ..
      ":" .. #app:notebook().cells)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_ADDN") then
    app:notebook():select(2)
    app:add_cell()
    print("SMOKE_ADDN=" .. #app:notebook().cells .. ":" ..
      app:notebook().active)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMEDGE") then
    app.ui.vim_normal = true
    app.ui:keypressed("m")
    app.ui:keypressed("a")
    app.ui:keypressed("j")
    app.ui:keypressed("'")
    app.ui:keypressed("a")
    local cell = app:notebook():selected()
    cell.source = "abc"
    cell.cursor = 4
    app.ui:keypressed("x")
    app.ui:keypressed(".")
    print("SMOKE_VIMEDGE=" .. tostring(app:notebook().active) .. ":" ..
      cell.source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_NBSUB") then
    local notebook = app:notebook()
    notebook.cells[1].source = "local old = 1"
    notebook.cells[2].source = "print(old)"
    app.ui:run_vim_command("%s/old/new/g")
    print("SMOKE_NBSUB=" .. notebook.cells[1].source .. "|" ..
      notebook.cells[2].source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMREC") then
    app.ui.vim_normal = true
    app.ui:keypressed("q")
    app.ui:keypressed("j")
    app.ui:keypressed("q")
    app.ui:keypressed("@")
    print("SMOKE_VIMREC=" .. tostring(app:notebook().active))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_SUBST") then
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
    app.ui.vim_normal = false
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
    local path = app:notebook()._path
    local after = #Format.list()
    app:delete_notebook(path)
    local final = #Format.list()
    app:create_folder("smoke-folder")
    app:new_notebook("notebooks/smoke-folder")
    local nested = app:notebook()._path
    local nested_ok = nested ~= nil and
      nested:match("^notebooks/smoke%-folder/") ~= nil
    app:rename_folder("notebooks/smoke-folder", "smoke-renamed")
    local renamed_ok = app:notebook()._path ==
      "notebooks/smoke-renamed/" .. app:notebook().name
    local title_ok = app:rename_title("Smoke identity") and
      app:notebook():title() == "Smoke identity"
    local moved_path = "notebooks/smoke-renamed/" .. app:notebook().name
    local move_ok = app:move_notebook(moved_path, "notebooks") and
      app:notebook()._path == "notebooks/" .. app:notebook().name
    local moved_name = app:notebook().name
    local duplicate_ok = app:duplicate_notebook() and
      app:notebook()._path ~= "notebooks/" .. moved_name
    app:delete_notebook(app:notebook()._path)
    app:delete_notebook("notebooks/" .. moved_name)
    app:delete_notebook("notebooks/smoke-renamed")
    local folder_gone = not lovr.filesystem.isDirectory(
      "notebooks/smoke-renamed")
    print(string.format("SMOKE_TREE=%d->%d->%d:%s:%s:%s:%s:%s:%s", before,
      after, final, tostring(nested_ok), tostring(renamed_ok),
      tostring(folder_gone), tostring(title_ok), tostring(move_ok),
      tostring(duplicate_ok)))
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
    local loaded = Extensions.user_loaded or {}
    local errors = Extensions.user_errors or {}
    print("SMOKE_USER_EXT=" .. #loaded .. " errors=" .. #errors .. " " .. table.concat(errors, " | "))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_WATCH") and
      Runtime.has_native_filesystem() then
    app.smoke_watch = true
    app.smoke_watch_started = lovr.timer.getTime()
    app.smoke_watch_touched = false
  end
  if os.getenv("LUANB_SMOKE_SUBST") or os.getenv("LUANB_SMOKE_VIMSEARCH") or
     os.getenv("LUANB_SMOKE_VIMCMD") or os.getenv("LUANB_SMOKE_TYPE") or
     os.getenv("LUANB_SMOKE_FOLDER") or os.getenv("LUANB_SMOKE_RENAME") or
     os.getenv("LUANB_SMOKE_TREE") or os.getenv("LUANB_SMOKE_EXT_PREFS") or
     os.getenv("LUANB_SMOKE_USER_EXT") or os.getenv("LUANB_SMOKE_WATCH") or
     os.getenv("LUANB_SMOKE_VIMEDGE") or os.getenv("LUANB_SMOKE_NBSUB") or
     os.getenv("LUANB_SMOKE_VIMREC") then
    return
  end

  -- Visual QA/demo: select and run one cell, then leave the window open.
  if os.getenv("LUANB_QA_SCREENSHOT") or os.getenv("LUANB_SMOKE_SCREENSHOT") then
    app.qa_screenshot = true
    app.qa_screenshot_after = tonumber(
      os.getenv("LUANB_QA_SCREENSHOT_AFTER") or "") or 3
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
    app.ui:open_tree()
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
  if os.getenv("LUANB_QA_NVIM") then
    app:open_nvim()
    print("FONT " .. tostring(app.font:getWidth("M")) .. ":" ..
      tostring(app.font:getHeight()) .. " cw=" ..
      tostring(app.nvim_view and app.nvim_view.cell_width) .. " ts=" ..
      tostring(app.nvim_view and app.nvim_view.text_scale))
    print("GRIDLINE [" .. tostring(app.nvim_session and
      app.nvim_session.grid:line(0)) .. "] fg=" ..
      tostring(app.nvim_session and
        app.nvim_session.grid.default_foreground) .. " bg=" ..
      tostring(app.nvim_session and
        app.nvim_session.grid.default_background))
    io.stdout:flush()
  elseif os.getenv("LUANB_QA_NVIM_NOTEBOOK") then
    app:open_nvim_notebook()
    if os.getenv("LUANB_QA_NVIM_SAVE") and app.nvim_session then
      app.nvim_session:input("<Esc>ggjccHELLO")
      for _ = 1, 5 do app.nvim_session:update(); os.execute("sleep 0.02") end
      app.ui:keypressed("f10")
      print("NVIM_SAVE [" .. tostring(app:notebook().cells[1].source) .. "]")
      io.stdout:flush()
      lovr.event.quit()
    end
    if os.getenv("LUANB_QA_NVIM_RUN") and app.nvim_session then
      app.nvim_session:request("nvim_win_set_cursor", { 0, { 5, 0 } })
      for _ = 1, 5 do app.nvim_session:update(); os.execute("sleep 0.01") end
      app.ui:keypressed("f5")
      print("NVIM_RUN active=" .. tostring(app:notebook().active))
      io.stdout:flush()
      lovr.event.quit()
    end
  end
  if os.getenv("LUANB_QA_NVIM_DELETE") then
    app:open_nvim_notebook()
    if app.nvim_session then
      local notebook = app:notebook()
      local encoded = NvimBuffer.encode(notebook.cells)
      local missing_rows = {}
      for index, line in ipairs(encoded) do
        if line ~= "-- %% cell 2 code" then
          missing_rows[#missing_rows + 1] = line
        end
      end
      app.nvim_session:set_lines(missing_rows, 1)
      for _ = 1, 5 do
        app.nvim_session:update(); os.execute("sleep 0.02")
      end
      local before = #notebook.cells
      app.ui:keypressed("f10")
      local prompted = app.nvim_delete_prompt ~= nil
      local unchanged = #notebook.cells == before
      app.ui:keypressed("escape")
      local cancelled = app.nvim_delete_prompt == nil and
        #notebook.cells == before
      app.ui:keypressed("f10")
      local reprompted = app.nvim_delete_prompt ~= nil
      local hold = os.getenv("LUANB_QA_NVIM_DELETE_HOLD") ~= nil
      if not hold then app.ui:keypressed("return") end
      print(string.format(
        "NVIM_DELETE prompted=%s unchanged=%s cancelled=%s reprompted=%s " ..
        "hold=%s before=%d after=%d", tostring(prompted),
        tostring(unchanged), tostring(cancelled), tostring(reprompted),
        tostring(hold), before, #notebook.cells))
      io.stdout:flush()
      if not hold then lovr.event.quit() end
    end
  end
  if os.getenv("LUANB_QA_NVIM_POPUP") then
    app:open_nvim()
    app.nvim_session:input("<Esc>")
    app.nvim_session:command("set completeopt=menu,menuone,noselect")
    app.nvim_session:set_lines({ "print(1)", "pairs({})", "pcall()" }, 1)
    app.nvim_session:input("Gopr")
    for _ = 1, 30 do app:update(); os.execute("sleep 0.02") end
    app.nvim_session:input("<C-n>")
    for _ = 1, 30 do app:update(); os.execute("sleep 0.02") end
  elseif os.getenv("LUANB_QA_NVIM_WARM") then
    app:open_nvim()
    app.ui:textinput("A")
    for _ = 1, 20 do app:update(); os.execute("sleep 0.03") end
    app:hide_nvim(true)
    app:open_nvim()
    app.ui:textinput("B")
    for _ = 1, 20 do app:update(); os.execute("sleep 0.03") end
    app:hide_nvim(true)
    print("NVIM_WARM [" .. tostring(app:notebook().cells[1].source) .. "]")
    io.stdout:flush()
    lovr.event.quit()
  elseif os.getenv("LUANB_QA_NVIM_EDIT") then
    app:open_nvim()
    if app.nvim_view then
      app.ui:textinput("i")
      app.ui:textinput("XYZ")
      for _ = 1, 20 do app:update(); os.execute("sleep 0.02") end
      app.ui:keypressed("f10")
      print("NVIM_EDIT [" .. app:notebook():selected().source .. "]")
      io.stdout:flush()
    end
  end
  if os.getenv("LUANB_QA_FIND") then
    app.ui:open_find()
    app.ui.find_query = os.getenv("LUANB_QA_FIND")
    app.ui:update_find()
  end
  local qa_scroll = tonumber(os.getenv("LUANB_QA_SCROLL") or "")
  if qa_scroll then
    app.ui.scroll = qa_scroll
    app.ui.scroll_to_selected = false
    app.ui.last_active = app:notebook().active
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
  if os.getenv("LUANB_SMOKE_WORKFLOW") then
    local notebook = app:notebook()
    notebook:select(1)
    local first_source = notebook.cells[1].source
    local second_source = notebook.cells[2].source
    app.ui:keypressed("down", { alt = true })
    local moved_down = notebook.active == 2 and
      notebook.cells[2].source == first_source and
      notebook.cells[1].source == second_source
    app.ui:keypressed("up", { alt = true })
    local moved_up = notebook.active == 1 and
      notebook.cells[1].source == first_source

    local headings = notebook:headings()
    local heading_ok = #headings >= 2
    if heading_ok then
      notebook:select(headings[2].index)
      app.ui:keypressed("up", { ctrl = true, shift = true })
      local previous_ok = notebook.active == headings[1].index
      app.ui:keypressed("down", { ctrl = true, shift = true })
      heading_ok = previous_ok and notebook.active == headings[2].index
    end

    app.ui:run_palette_command("collapse-headings")
    local collapsed_ok = true
    for _, cell in ipairs(notebook.cells) do
      if Notebook.heading_level(cell) and not cell.collapsed then
        collapsed_ok = false
      end
    end
    app.ui:run_palette_command("expand-headings")
    local expanded_ok = true
    for _, cell in ipairs(notebook.cells) do
      if Notebook.heading_level(cell) and cell.collapsed then
        expanded_ok = false
      end
    end

    notebook:select(1)
    local copied_source = notebook.cells[1].source
    app.ui:keypressed("c", { ctrl = true, shift = true })
    local clipboard_ok = lovr.system.getClipboardText() == copied_source

    local old_output = notebook.cells[1].output
    notebook.cells[1].output = "smoke clipboard output"
    app.ui:keypressed("c", { ctrl = true, alt = true })
    local output_clipboard_ok =
      lovr.system.getClipboardText() == "smoke clipboard output"
    notebook.cells[1].output = old_output

    notebook:select(2)
    notebook.cells[2].cursor = #notebook.cells[2].source + 1
    lovr.system.setClipboardText("PASTE")
    app.ui:keypressed("v", { ctrl = true })
    local paste_ok = notebook.cells[2].source:find("PASTE", 1, true) ~= nil
    notebook:undo()

    local task_cell, task_line
    for cell_index, cell in ipairs(notebook.cells) do
      if cell.kind == "markdown" then
        local line_number = 0
        for line in ((cell.source or "") .. "\n"):gmatch("(.-)\n") do
          line_number = line_number + 1
          if line:find("- [ ]", 1, true) then
            task_cell, task_line = cell_index, line_number
            break
          end
        end
      end
      if task_cell then break end
    end
    local task_ok = false
    if task_cell then
      local before = notebook.cells[task_cell].source
      app.ui.task_rects = {
        { x = 0, y = 0, w = 20, h = 20, cell = task_cell, line = task_line },
      }
      app.ui:mousepressed(5, 5, 1)
      task_ok = notebook.cells[task_cell].source ~= before
      notebook:undo()
    end

    app.ui:keypressed("f11")
    app.ui:textinput("Tables")
    local outline_ok = #app.ui.outline_matches == 1
    local outline_target = app.ui.outline_matches[1]
    app.ui:keypressed("return")
    outline_ok = outline_ok and outline_target ~= nil and
      notebook.active == outline_target.index and not app.ui.show_outline

    notebook:select(2)
    local duplicate_source = notebook.cells[2].source
    local cells_before_duplicate = #notebook.cells
    app.ui:keypressed("d", { alt = true })
    local duplicate_ok = #notebook.cells == cells_before_duplicate + 1 and
      notebook.cells[3].source == duplicate_source
    notebook:undo()

    app.ui:keypressed("g", { ctrl = true, alt = true })
    app.ui:textinput("3")
    app.ui:keypressed("return")
    local goto_ok = notebook.active == 3

    notebook:select(1)
    local clear_cell = notebook.cells[1]
    local old_output2 = clear_cell.output
    local old_error2 = clear_cell.error
    local old_scene2 = clear_cell.scene
    local old_widgets2 = clear_cell.widgets
    clear_cell.output = "clear me"
    clear_cell.error = "boom"
    clear_cell.scene = "cube"
    clear_cell.widgets = { { id = "w" } }
    app.ui:keypressed("x", { ctrl = true, alt = true })
    local clear_ok = clear_cell.output == "" and clear_cell.error == nil and
      clear_cell.scene == nil and #clear_cell.widgets == 0
    clear_cell.output = old_output2
    clear_cell.error = old_error2
    clear_cell.scene = old_scene2
    clear_cell.widgets = old_widgets2

    app.ui:keypressed("t", { ctrl = true })
    app.ui:textinput("lua")
    local tag_ok = #app.ui.tag_entries == 1 and
      app.ui.tag_entries[1].tag == "lua"
    app.ui:keypressed("return")
    tag_ok = tag_ok and not app.ui.show_tags and
      app.ui.find_query == "#lua"
    app.ui:keypressed("escape")

    app:set_tab(1)
    app.ui.link_rects = {
      { x = 0, y = 0, w = 20, h = 20, target = "Second kernel" },
    }
    app.ui:mousepressed(5, 5, 1)
    local wiki_ok = app.active == 2 and
      app:notebook():title() == "Second kernel"
    app:set_tab(1)

    notebook.dirty = true
    app:save_all()
    local save_all_ok = notebook.dirty == false and
      app.status:find("saved", 1, true) ~= nil
    local restart_all_ok = app:restart_all_kernels() and
      app.status:find("restarted", 1, true) ~= nil

    local output_cell = notebook.cells[1]
    local old_output3 = output_cell.output
    local output_lines = {}
    for line = 1, 8 do output_lines[line] = "line " .. line end
    output_cell.output = table.concat(output_lines, "\n")
    app:set_outputs_expanded(true)
    local expand_ok = output_cell.output_expanded == true
    app:set_outputs_expanded(false)
    local collapse_ok = output_cell.output_expanded == false
    output_cell.output = old_output3

    notebook:select(2)
    local original_line_cell = notebook.cells[2].source
    notebook.cells[2].source = "a\nb"
    notebook.cells[2].cursor = 3
    app.ui:keypressed("/", { ctrl = true })
    app.ui:keypressed("]", { ctrl = true })
    app.ui:keypressed("[", { ctrl = true })
    app.ui:keypressed("d", { ctrl = true, shift = true })
    notebook.cells[2].cursor = 3
    app.ui:keypressed("up", { alt = true, shift = true })
    local line_ops_ok = notebook.cells[2].source == "-- b\na\n-- b"

    notebook.cells[2].source = "a\nb\nc"
    notebook.cells[2].cursor = 1
    app.ui:keypressed("l", { ctrl = true, alt = true })
    app.ui:textinput("3")
    app.ui:keypressed("return")
    local go_line_ok = notebook.cells[2].cursor == 5 and
      not app.ui.show_cell_prompt
    notebook.cells[2].source = "alpha beta"
    notebook.cells[2].cursor = 1
    app.ui:keypressed("delete", { ctrl = true })
    local word_ok = notebook.cells[2].source == "beta"
    notebook.cells[2].source = "alpha\n  beta"
    notebook.cells[2].cursor = 3
    app.ui:keypressed("j", { ctrl = true })
    local join_ok = notebook.cells[2].source == "alpha beta"
    notebook.cells[2].source = "a\nb"
    notebook.cells[2].cursor = 2
    app.ui:keypressed("home", { ctrl = true })
    app.ui:keypressed("end", { ctrl = true })
    local home_end_ok = notebook.cells[2].cursor == 4
    notebook.cells[2].source = original_line_cell
    notebook.cells[2].cursor = 1

    local exec_count = #notebook.cells
    local inserted = app:run_and_insert()
    local insert_ok = inserted and #notebook.cells == exec_count + 1
    notebook.cells[2].running = false
    notebook:delete_cell(notebook.active)
    notebook:select(2)
    app._run_all_position = 1
    app._run_all_stop = #notebook.cells
    local stop_ok = app:stop_run_all() and app._run_all_position == nil
    local rerun_ok = app:clear_and_rerun()
    notebook.cells[2].running = false
    local restart_clear_ok = app:restart_and_clear()
    print("SMOKE_EXEC=" .. tostring(insert_ok) .. ":" ..
      tostring(stop_ok) .. ":" .. tostring(rerun_ok) .. ":" ..
      tostring(restart_clear_ok))

    app.smoke_workflow_ok = moved_down and moved_up and heading_ok and
      collapsed_ok and expanded_ok and clipboard_ok and output_clipboard_ok and
      task_ok and outline_ok and clear_ok and tag_ok and wiki_ok and
      duplicate_ok and goto_ok and paste_ok and save_all_ok and
      restart_all_ok and expand_ok and collapse_ok and line_ops_ok and
      go_line_ok and word_ok and join_ok and home_end_ok and insert_ok and
      stop_ok and rerun_ok and restart_clear_ok
    print(string.format(
      "SMOKE_WORKFLOW_SHORTCUTS=%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s",
      tostring(moved_down), tostring(moved_up), tostring(heading_ok),
      tostring(collapsed_ok), tostring(expanded_ok),
      tostring(clipboard_ok), tostring(output_clipboard_ok),
      tostring(task_ok), tostring(outline_ok), tostring(clear_ok),
      tostring(tag_ok), tostring(wiki_ok), tostring(duplicate_ok),
      tostring(goto_ok), tostring(paste_ok), tostring(save_all_ok),
      tostring(restart_all_ok), tostring(expand_ok), tostring(collapse_ok),
      tostring(line_ops_ok), tostring(go_line_ok), tostring(word_ok),
      tostring(join_ok), tostring(home_end_ok)))

    local workflow = Notebook.new({
      name = "workflow-smoke.luanb",
      cells = {
        { kind = "code", output = "", source = "workflow_marker = (workflow_marker or 0) + 1\nprint(\"workflow marker\", workflow_marker)" },
        { kind = "code", output = "", source = "print(\"workflow repeat\", workflow_marker)" },
        { kind = "code", output = "", source = "print(\"workflow third\", workflow_marker)" },
      },
    })
    app.notebooks[#app.notebooks + 1] = workflow
    app.active = #app.notebooks
    app.supervisor:open(app:kernel_id(workflow))
    app.smoke = true
    app.smoke_start = lovr.timer.getTime()
    app.smoke_workflow_phase = "prepare"
    workflow:select(1)
    app:run()
  elseif os.getenv("LUANB_SMOKE_VIMEDGE") then
    app.ui.vim_normal = true
    app.ui:keypressed("m")
    app.ui:keypressed("a")
    app.ui:keypressed("j")
    app.ui:keypressed("'")
    app.ui:keypressed("a")
    local cell = app:notebook():selected()
    cell.source = "abc"
    cell.cursor = 4
    app.ui:keypressed("x")
    app.ui:keypressed(".")
    print("SMOKE_VIMEDGE=" .. tostring(app:notebook().active) .. ":" ..
      cell.source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_NBSUB") then
    local notebook = app:notebook()
    notebook.cells[1].source = "local old = 1"
    notebook.cells[2].source = "print(old)"
    app.ui:run_vim_command("%s/old/new/g")
    print("SMOKE_NBSUB=" .. notebook.cells[1].source .. "|" ..
      notebook.cells[2].source)
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_VIMREC") then
    app.ui.vim_normal = true
    app.ui:keypressed("q")
    app.ui:keypressed("j")
    app.ui:keypressed("q")
    app.ui:keypressed("@")
    print("SMOKE_VIMREC=" .. tostring(app:notebook().active))
    lovr.event.quit()
  elseif os.getenv("LUANB_SMOKE_SUBST") then
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
    app.ui.vim_normal = false
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
    local path = app:notebook()._path
    local after = #Format.list()
    app:delete_notebook(path)
    local final = #Format.list()
    app:create_folder("smoke-folder")
    app:new_notebook("notebooks/smoke-folder")
    local nested = app:notebook()._path
    local nested_ok = nested ~= nil and
      nested:match("^notebooks/smoke%-folder/") ~= nil
    app:rename_folder("notebooks/smoke-folder", "smoke-renamed")
    local renamed_ok = app:notebook()._path ==
      "notebooks/smoke-renamed/" .. app:notebook().name
    local title_ok = app:rename_title("Smoke identity") and
      app:notebook():title() == "Smoke identity"
    local moved_path = "notebooks/smoke-renamed/" .. app:notebook().name
    local move_ok = app:move_notebook(moved_path, "notebooks") and
      app:notebook()._path == "notebooks/" .. app:notebook().name
    local moved_name = app:notebook().name
    local duplicate_ok = app:duplicate_notebook() and
      app:notebook()._path ~= "notebooks/" .. moved_name
    app:delete_notebook(app:notebook()._path)
    app:delete_notebook("notebooks/" .. moved_name)
    app:delete_notebook("notebooks/smoke-renamed")
    local folder_gone = not lovr.filesystem.isDirectory(
      "notebooks/smoke-renamed")
    print(string.format("SMOKE_TREE=%d->%d->%d:%s:%s:%s:%s:%s:%s", before,
      after, final, tostring(nested_ok), tostring(renamed_ok),
      tostring(folder_gone), tostring(title_ok), tostring(move_ok),
      tostring(duplicate_ok)))
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
    local loaded = Extensions.user_loaded or {}
    local errors = Extensions.user_errors or {}
    print("SMOKE_USER_EXT=" .. #loaded .. " errors=" .. #errors .. " " .. table.concat(errors, " | "))
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
     os.getenv("LUANB_SMOKE_PLOT") or os.getenv("LUANB_SMOKE_POLAR") or
     os.getenv("LUANB_SMOKE_GRID") or
     os.getenv("LUANB_SMOKE_WIDGET") or
     os.getenv("LUANB_SMOKE_WIDGET_EVENT") or
     os.getenv("LUANB_SMOKE_INPUT") then
    app.smoke = true
    app.smoke_start = lovr.timer.getTime()
    local function find_cell(marker)
      for index, cell in ipairs(app:notebook().cells) do
        if (cell.source or ""):find(marker, 1, true) then return index end
      end
    end
    local target
    if os.getenv("LUANB_SMOKE_SCENE") or os.getenv("LUANB_SMOKE_INPUT") then
      target = find_cell('return { scene = "cube" }')
    elseif os.getenv("LUANB_SMOKE_PLOT") then
      target = find_cell('title = "sin(x)"')
    elseif os.getenv("LUANB_SMOKE_POLAR") then
      target = find_cell('title = "polar rose"')
    elseif os.getenv("LUANB_SMOKE_GRID") then
      target = find_cell('return { scene = "grid" }')
    elseif os.getenv("LUANB_SMOKE_WIDGET") or
           os.getenv("LUANB_SMOKE_WIDGET_EVENT") then
      target = find_cell("widgets.slider(")
    end
    if target then app:notebook():select(target) end
    app:run()
  end
end

function lovr.update(dt)
  if app == nil then return end
  local profile_start = os.getenv("LUANB_PROFILE") and lovr.timer.getTime()
  local ok, err = pcall(App.update, app)
  if not ok then
    app.status = "update error: " .. tostring(err)
    print("UPDATE_ERROR " .. tostring(err))
    return
  end
  if profile_start then
    local elapsed = lovr.timer.getTime() - profile_start
    if elapsed > 0.02 then
      print(string.format("PROFILE update %.3fs", elapsed))
      io.stdout:flush()
    end
  end
  if app.smoke then
    local notebook = app:notebook()
    local cell = notebook.cells[notebook.active]
    if os.getenv("LUANB_SMOKE_WORKFLOW") then
      local first, second, third =
        notebook.cells[1], notebook.cells[2], notebook.cells[3]
      if app.smoke_workflow_phase == "prepare" then
        if not first.running and
           first.output:find("workflow marker\t1", 1, true) then
          app.ui:keypressed("f5", { ctrl = true, shift = true })
          app.smoke_workflow_phase = "run-all"
          app.smoke_start = lovr.timer.getTime()
        elseif lovr.timer.getTime() - app.smoke_start > 8 then
          print("SMOKE_WORKFLOW=timeout:prepare:" ..
            tostring(first.output))
          app.smoke = false
          lovr.event.quit()
        end
      elseif app.smoke_workflow_phase == "run-all" then
        if app._run_all_position == nil and not first.running and
           not second.running and not third.running and
           app.status:find("all code cells finished", 1, true) then
          local first_ok =
            first.output:find("workflow marker\t1", 1, true) ~= nil
          local second_ok =
            second.output:find("workflow repeat\t1", 1, true) ~= nil
          local third_ok =
            third.output:find("workflow third\t1", 1, true) ~= nil
          if app.smoke_workflow_ok and first_ok and second_ok and third_ok then
            app.smoke_workflow_first_output = first.output
            notebook:select(2)
            app.ui:keypressed("return", { ctrl = true, alt = true })
            app.smoke_workflow_phase = "run-below"
            app.smoke_start = lovr.timer.getTime()
          else
            print("SMOKE_WORKFLOW=false:" .. tostring(first_ok) .. ":" ..
              tostring(second_ok) .. ":" .. tostring(third_ok) .. ":" ..
              tostring(first.output) .. "|" .. tostring(second.output) ..
              "|" .. tostring(third.output))
            app.smoke = false
            lovr.event.quit()
          end
        elseif lovr.timer.getTime() - app.smoke_start > 15 then
          print("SMOKE_WORKFLOW=timeout:run-all:" .. tostring(app.status) ..
            ":" .. tostring(first.output) .. "|" .. tostring(second.output) ..
            "|" .. tostring(third.output))
          app.smoke = false
          lovr.event.quit()
        end
      elseif app.smoke_workflow_phase == "run-below" then
        if app._run_all_position == nil and not first.running and
           not second.running and not third.running and
           app.status:find("all code cells below finished", 1, true) then
          local first_unchanged = first.output ==
            app.smoke_workflow_first_output
          local second_ok =
            second.output:find("workflow repeat\t1", 1, true) ~= nil
          local third_ok =
            third.output:find("workflow third\t1", 1, true) ~= nil
          if first_unchanged and second_ok and third_ok then
            app.smoke_workflow_third_output = third.output
            notebook:select(2)
            app.ui:keypressed("up", { ctrl = true, alt = true })
            app.smoke_workflow_phase = "run-above"
            app.smoke_start = lovr.timer.getTime()
          else
            print("SMOKE_WORKFLOW=false:below:" ..
              tostring(first_unchanged) .. ":" .. tostring(second_ok) ..
              ":" .. tostring(third_ok))
            app.smoke = false
            lovr.event.quit()
          end
        elseif lovr.timer.getTime() - app.smoke_start > 12 then
          print("SMOKE_WORKFLOW=timeout:run-below:" .. tostring(app.status) ..
            ":" .. tostring(first.output) .. "|" .. tostring(second.output) ..
            "|" .. tostring(third.output))
          app.smoke = false
          lovr.event.quit()
        end
      elseif app.smoke_workflow_phase == "run-above" then
        if app._run_all_position == nil and not first.running and
           not second.running and not third.running and
           app.status:find("all code cells above finished", 1, true) then
          local first_ok =
            first.output:find("workflow marker\t2", 1, true) ~= nil
          local second_ok =
            second.output:find("workflow repeat\t2", 1, true) ~= nil
          local third_unchanged = third.output ==
            app.smoke_workflow_third_output
          local ok = first_ok and second_ok and third_unchanged
          print("SMOKE_WORKFLOW=" .. tostring(ok) .. ":" ..
            tostring(first_ok) .. ":" .. tostring(second_ok) .. ":" ..
            tostring(third_unchanged) .. ":" .. tostring(first.output) .. "|" ..
            tostring(second.output) .. "|" .. tostring(third.output))
          app.smoke = false
          lovr.event.quit()
        elseif lovr.timer.getTime() - app.smoke_start > 12 then
          print("SMOKE_WORKFLOW=timeout:run-above:" .. tostring(app.status) ..
            ":" .. tostring(first.output) .. "|" .. tostring(second.output) ..
            "|" .. tostring(third.output))
          app.smoke = false
          lovr.event.quit()
        end
      end
    elseif os.getenv("LUANB_SMOKE_SUBST") then
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
    app.ui.vim_normal = false
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
    local path = app:notebook()._path
    local after = #Format.list()
    app:delete_notebook(path)
    local final = #Format.list()
    app:create_folder("smoke-folder")
    app:new_notebook("notebooks/smoke-folder")
    local nested = app:notebook()._path
    local nested_ok = nested ~= nil and
      nested:match("^notebooks/smoke%-folder/") ~= nil
    app:rename_folder("notebooks/smoke-folder", "smoke-renamed")
    local renamed_ok = app:notebook()._path ==
      "notebooks/smoke-renamed/" .. app:notebook().name
    local title_ok = app:rename_title("Smoke identity") and
      app:notebook():title() == "Smoke identity"
    local moved_path = "notebooks/smoke-renamed/" .. app:notebook().name
    local move_ok = app:move_notebook(moved_path, "notebooks") and
      app:notebook()._path == "notebooks/" .. app:notebook().name
    local moved_name = app:notebook().name
    local duplicate_ok = app:duplicate_notebook() and
      app:notebook()._path ~= "notebooks/" .. moved_name
    app:delete_notebook(app:notebook()._path)
    app:delete_notebook("notebooks/" .. moved_name)
    app:delete_notebook("notebooks/smoke-renamed")
    local folder_gone = not lovr.filesystem.isDirectory(
      "notebooks/smoke-renamed")
    print(string.format("SMOKE_TREE=%d->%d->%d:%s:%s:%s:%s:%s:%s", before,
      after, final, tostring(nested_ok), tostring(renamed_ok),
      tostring(folder_gone), tostring(title_ok), tostring(move_ok),
      tostring(duplicate_ok)))
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
    local loaded = Extensions.user_loaded or {}
    local errors = Extensions.user_errors or {}
    print("SMOKE_USER_EXT=" .. #loaded .. " errors=" .. #errors .. " " .. table.concat(errors, " | "))
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
  local draw_start = os.getenv("LUANB_PROFILE") and lovr.timer.getTime()
  local width, height = window:getDimensions()
  local scale = app.ui_scale or 1
  local logical_width = math.max(320, math.floor(width / scale))
  local logical_height = math.max(240, math.floor(height / scale))
  local canvas, canvas_pass = app:ensure_canvas(width, height)
  canvas_pass:reset()
  if app.screenshot_requested then
    app.screenshot_requested = false
    app.screenshot_readback = canvas:newReadback()
  end
  -- Always lay down an opaque base before the UI so a render failure cannot
  -- leave the window black.
  canvas_pass:setColor(1, 1, 1, 1)
  canvas_pass:plane(width / 2, height / 2, 0, width, height)
  local ok, passes = pcall(UI.draw, app.ui, canvas_pass, logical_width,
    logical_height)
  if not ok then
    local message = tostring(passes)
    app.status = "draw error: " .. message
    print("DRAW_ERROR " .. message)
    passes = {}
    if app.font then
      canvas_pass:setFont(app.font)
      canvas_pass:setColor(0.55, 0.08, 0.10, 1)
      canvas_pass:text("render error: " .. message, 24, 24, 0, 0.8)
    end
  end
  window:fill(canvas)
  passes[#passes + 1] = canvas_pass
  passes[#passes + 1] = window
  local result = lovr.graphics.submit(passes)
  if draw_start then
    local elapsed = lovr.timer.getTime() - draw_start
    if elapsed > 0.02 then
      print(string.format("PROFILE draw %.3fs", elapsed))
      io.stdout:flush()
    end
  end
  return result
end

function lovr.keyreleased(key)
  if app then app.ui:keyreleased(key) end
end

function lovr.textinput(text, code)
  if app then app.ui:textinput(text) end
end

function lovr.keypressed(key)
  if app == nil then return end
  local ok, err = pcall(UI.keypressed, app.ui, key)
  if not ok then
    app.status = "key error: " .. tostring(err)
    print("KEY_ERROR " .. tostring(err))
  end
end

function lovr.mousepressed(x, y, button)
  if app then
    local scale = app.ui_scale or 1
    app.ui:mousepressed(x / scale, y / scale, button)
  end
end

function lovr.mousemoved(x, y, dx, dy)
  if app then
    local scale = app.ui_scale or 1
    app.ui:mousemoved(x / scale, y / scale, dx / scale, dy / scale)
  end
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
  if app and app.save_session then app:save_session() end
  if app and app.supervisor.close then app.supervisor:close() end
  if app and app.lsp_in then app.lsp_in:push("__quit") end
  if app and app.close_nvim then app:close_nvim(false) end
end

function lovr.filechanged(path, action)
  local id = path:match("extensions/([a-z][a-z0-9_-]*)%.lua$")
  if app and id and id ~= "init" and id ~= "loader" and id ~= "manifest" then
    app:reload_extension(id)
  end
end
