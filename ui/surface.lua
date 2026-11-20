--
-- A render-target surface for one extension/notebook cell.
--
-- Each surface owns a Texture and a Pass.  The extension renderer records into
-- the Pass; the notebook composites the Texture into the cell.  Kernels never
-- see either object.
--
local Theme = require("ui.theme")
local Surface = {}
Surface.__index = Surface

function Surface.new()
  return setmetatable({
    width = 0,
    height = 0,
    texture = nil,
    pass = nil,
    state = {},
  }, Surface)
end

function Surface:ensure(renderer, width, height)
  width = math.max(1, math.floor(width))
  height = math.max(1, math.floor(height))
  if width == self.width and height == self.height and self.texture then
    self.renderer = renderer
    return
  end
  self.width = width
  self.height = height
  self.texture = lovr.graphics.newTexture(width, height, {
    mipmaps = false,
    samples = 1,
    label = "notebook-extension",
  })
  self.pass = lovr.graphics.newPass(self.texture)
  self.pass:setClear(Theme.mode == "light" and 0.97 or 0.02,
      Theme.mode == "light" and 0.98 or 0.025,
      Theme.mode == "light" and 1 or 0.04, 1)
  self.renderer = renderer
  if renderer and renderer.resize then
    renderer.resize(self.state, width, height)
  end
end

function Surface:render(renderer, time)
  local pass = self.pass
  pass:reset()
  pass:setClear(Theme.mode == "light" and 0.97 or 0.02,
      Theme.mode == "light" and 0.98 or 0.025,
      Theme.mode == "light" and 1 or 0.04, 1)
  renderer.render(pass, time or 0, self.width, self.height, self.state)
end

function Surface:render_display(descriptor, time)
  local pass = self.pass
  pass:reset()
  pass:setClear(Theme.mode == "light" and 0.97 or 0.02,
      Theme.mode == "light" and 0.98 or 0.025,
      Theme.mode == "light" and 1 or 0.04, 1)
  require("extensions.support.display_list").replay(pass, descriptor,
    self.width, self.height)
end

function Surface:pointer(event)
  local renderer = self.renderer
  if renderer and renderer.pointer then
    renderer.pointer(self.state, event)
  end
end

function Surface:key(event)
  local renderer = self.renderer
  if renderer and renderer.key then
    renderer.key(self.state, event)
  end
end

function Surface:text(value)
  local renderer = self.renderer
  if renderer and renderer.text then
    renderer.text(self.state, value)
  end
end

function Surface:composite(pass, x, y, width, height, scale)
  -- The fill shader samples the texture directly and is not affected by
  -- scene lighting.  pass:draw(texture) uses the lit default material and can
  -- come out black without lights.  Viewports are physical pixels.
  scale = scale or 1
  pass:setColor(1, 1, 1, 1)
  pass:setViewport(x * scale, y * scale, width * scale, height * scale)
  pass:fill(self.texture)
  pass:setViewport()
end

return Surface
