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
  local scale_ok, scale_value = pcall(lovr.filesystem.read, "ui_scale.txt")
  if scale_ok and tonumber(scale_value) then
    self.ui_scale = math.max(0.7, math.min(2, tonumber(scale_value)))
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
  if self._run_all_position ~= nil then self:_run_next_all() end
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
  for index = self._run_all_position + 1, #notebook.cells do
    if notebook.cells[index].kind == "code" then
      self._run_all_position = index
      notebook:select(index)
      self.scroll_to_selected = true
      self:run()
      return
    end
  end
  self._run_all_position = nil
  self.status = "all code cells finished"
end

function App:run_all()
  self._run_all_position = 0
  self.status = "running all code cells"
  self:_run_next_all()
end

function App:export_html()
  local notebook = self:notebook()
  local safe = notebook.name:gsub("[^%w_.-]", "_"):gsub("%.luanb$", "")
  local path = "exports/" .. safe .. ".html"
  pcall(lovr.filesystem.createDirectory, "exports")
  local ok, err = pcall(lovr.filesystem.write, path,
    require("notebook.format").to_html(notebook))
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

function App:restart_kernel()
  self._run_all_position = nil
  local id = "nb" .. self.active
  if self.supervisor.restart then
    self.supervisor:restart(id)
    local notebook = self:notebook()
    for _, cell in ipairs(notebook.cells) do cell.running = false end
    self.status = "kernel restarted"
  else
    self.status = "kernel restart is unavailable for this backend"
  end
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

function App:open_nvim()
  local cell = self:notebook():selected()
  if cell.kind ~= "code" and cell.kind ~= "markdown" then
    self.status = "Neovim editor is for code and markdown cells"
    return
  end
  if self.nvim_session then
    self.nvim_session:input("<Esc>")
    self.nvim_session:update()
    local lines = {}
    for source_line in ((cell.source or "") .. "\n"):gmatch("(.-)\n") do
      lines[#lines + 1] = source_line
    end
    local loaded, load_error = self:load_nvim_buffer(lines,
      cell.kind == "markdown" and "markdown" or "lua")
    if not loaded then
      self:close_nvim(false)
      self.status = "Neovim reload failed: " .. tostring(load_error)
      return self:open_nvim()
    end
    self.show_nvim, self.nvim_notebook = true, false
    self.status = "Neovim (warm): F10 save, F5 run"
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
  for _ = 1, 150 do
    session:update()
    if session.grid:line(0):find("%S") then break end
    os.execute("sleep 0.02")
  end
  session:input("i")
  for _ = 1, 5 do session:update(); os.execute("sleep 0.01") end
  self.nvim_session = session
  self.nvim_view = require("ui.nvim").new(session, self.nvim_font or self.font)
  self.nvim_path = path
  self.show_nvim = true
  self.status = "Neovim: F10 save, F9 discard"
end

function App:load_nvim_buffer(lines, filetype)
  local session = self.nvim_session
  if session == nil then return false end
  pcall(function()
    session:input("<Esc>")
    session:update()
  end)
  local ok, err = session:set_lines(lines, 1)
  if not ok then return nil, err end
  session:command("set filetype=" .. filetype)
  -- A reused buffer should not carry the previous cell's undo history.
  session:command("set undolevels=-1")
  session:command("set undolevels=1000")
  session:input("i")
  return true
end

function App:close_nvim(save, keep)
  if self.nvim_session == nil then return end
  local session = self.nvim_session
  local cursor_row, cursor_col = 0, 0
  if session.grid then
    cursor_row = math.max(0, session.grid.cursor.row or 0)
    cursor_col = math.max(0, session.grid.cursor.col or 0)
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
      return
    end
    lines = value
    if lines == nil or #lines == 0 then
      self.status = "Neovim save failed: " .. tostring(err or "empty buffer")
      return
    end
    local cursor_ok, cursor = pcall(function()
      return session:request("nvim_win_get_cursor", { 0 })
    end)
    if cursor_ok and type(cursor) == "table" then
      cursor_row = math.max(0, cursor[1] or cursor_row)
      cursor_col = math.max(0, cursor[2] or cursor_col)
    end
  end

  local applied = false
  if save and lines then
    if self.nvim_notebook then
      local sources = NvimBuffer.decode(lines)
      local notebook = self:notebook()
      local changed = false
      for index, source in pairs(sources) do
        local cell = notebook.cells[index]
        if cell and cell.source ~= source then changed = true end
      end
      if changed then notebook:push_undo("Neovim notebook edit") end
      for index, source in pairs(sources) do
        local cell = notebook.cells[index]
        if cell then cell.source = source end
      end
      notebook.dirty = changed or notebook.dirty
      applied = true
      self.status = changed and "applied Neovim changes; F6 writes the file" or
        "no Neovim changes; F6 writes the file"
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
  self.nvim_cells = {}
  self.nvim_cell_rows = {}
end

function App:hide_nvim(save)
  return self:close_nvim(save, true)
end

function App:run_nvim_cell()
  if self.nvim_session == nil then return end
  local row = (self.nvim_session.grid.cursor.row or 0) + 1
  pcall(function()
    self.nvim_session:input("<Esc>")
    self.nvim_session:update()
    local cursor = self.nvim_session:request("nvim_win_get_cursor", { 0 })
    if type(cursor) == "table" and cursor[1] then
      row = cursor[1] + 1
    end
  end)
  local index = self:notebook().active
  for _, entry in ipairs(self.nvim_cell_rows or {}) do
    if entry.row <= row then index = entry.index end
  end
  self:hide_nvim(true)
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
  local lines, rows = NvimBuffer.encode(notebook.cells)
  local cells = {}
  for _, entry in ipairs(rows) do cells[entry.index] = true end
  if #lines == 0 then self.status = "notebook has no code cells"; return end
  if self.nvim_session then
    self.nvim_session:input("<Esc>")
    self.nvim_session:update()
    local loaded, load_error = self:load_nvim_buffer(lines, "lua")
    if not loaded then
      self:close_nvim(false)
      self.status = "Neovim reload failed: " .. tostring(load_error)
      return self:open_nvim_notebook()
    end
    self.nvim_cells, self.nvim_cell_rows = cells, rows
    self.show_nvim, self.nvim_notebook = true, true
    self.status = "Neovim notebook (warm): F10 save, F5 run"
    return
  end
  local path = os.tmpname() .. ".lua"
  local handle = assert(io.open(path, "wb"))
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
  for _ = 1, 150 do
    session:update()
    if session.grid:line(0):find("%S") then break end
    os.execute("sleep 0.02")
  end
  session:input("i")
  self.nvim_session, self.nvim_cells = session, cells
  self.nvim_cell_rows = rows
  self.nvim_view = require("ui.nvim").new(session, self.nvim_font or self.font)
  self.nvim_path, self.nvim_notebook, self.show_nvim = path, true, true
  self.status = "Neovim notebook: F10 save, F5 run cell"
end

function App:save()
  local ok, path, absolute = pcall(Format.save, self:notebook())
  if not ok then
    self.status = "save failed: " .. tostring(path)
    return
  end
  self.status = "saved " .. tostring(absolute)
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
  self.notebooks[self.active] = loaded
  self.scroll = 0
  self.status = "loaded " .. loaded.name
end

function App:update()
  if self.show_nvim then
    if self.nvim_view then self.nvim_view:update() end
    if self.nvim_session and self.nvim_session.exited then
      self:close_nvim(false)
      self.status = "Neovim exited unexpectedly"
    end
  elseif self.ui then
    self.ui:update()
  end
  self.supervisor:poll()
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
     not self.screenshot_readback and lovr.timer.getTime() > 3 then
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
     not self.screenshot_readback and lovr.timer.getTime() > 3 and
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
  if os.getenv("LUANB_QA_NVIM") then
    app:open_nvim()
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
  if os.getenv("LUANB_QA_NVIM_WARM") then
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
  if os.getenv("LUANB_SMOKE_VIMEDGE") then
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
