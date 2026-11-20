local root = (arg and arg[0] or "tests/nvim_mouse.lua"):match("^(.*)/tests/") or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
_G.lovr = { system = { isKeyDown = function() return false end,
  getMousePosition = function() return 0, 0 end } }
local UI = require("ui.notebook")
local pressed
local app = {
  show_nvim = true,
  nvim_view = {
    mousepressed = function(_, x, y, button)
      pressed = { x, y, button }
    end,
  },
}
local ui = UI.new(app)
ui:mousepressed(12, 34, 1)
assert(pressed and pressed[1] == 12 and pressed[3] == 1)
ui:mousereleased(12, 34, 1)
ui:mousemoved(12, 34, 0, 0)
assert(ui.app.show_nvim)
print("nvim mouse routing ok")
