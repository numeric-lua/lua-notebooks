-- Standalone Neovim-in-LÖVR spike.
local Session = require("notebook.nvim.session")
local NvimView = require("ui.nvim")

local view
local session
local font

function lovr.load()
  local path = "/tmp/lua-notebooks-nvim-demo.lua"
  local sample = assert(io.open(path, "wb"))
  sample:write([[
-- Neovim inside LÖVR
local function greet(name)
  print("hello, " .. name)
end

greet("notebook")
]])
  sample:close()
  session = Session.new({ cols = 100, rows = 30, file = path })
  font = lovr.graphics.newFont("assets/DejaVuSansMono.ttf", 18)
  view = NvimView.new(session, font)
end

function lovr.update(dt)
  if view then view:update() end
end

function lovr.draw(pass)
  if view then view:draw(pass, 20, 20, 1200, 760, 1) end
end

function lovr.keypressed(key)
  if key == "f10" then
    if session then session:close() end
    lovr.event.quit()
  elseif view then
    view:keypressed(key)
  end
end

function lovr.textinput(text)
  if view then view:textinput(text) end
end

function lovr.quit()
  if session then session:close() end
end
