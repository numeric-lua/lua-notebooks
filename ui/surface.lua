--
-- A render-target surface for one extension/notebook cell.
--
-- Each surface owns a Texture and a Pass.  The extension renderer records into
-- the Pass; the notebook composites the Texture into the cell.  Kernels never
-- see either object.
--
local Surface = {}
Surface.__index = Surface

function Surface.new()
  return setmetatable({
    width = 0,
    height = 0,
    texture = nil,
    pass = nil,
  }, Surface)
end

function Surface:ensure(width, height)
  width = math.max(1, math.floor(width))
  height = math.max(1, math.floor(height))
  if width == self.width and height == self.height and self.texture then
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
  self.pass:setClear(0.02, 0.025, 0.04, 1)
end

function Surface:render(renderer, time)
  local pass = self.pass
  pass:reset()
  pass:setClear(0.02, 0.025, 0.04, 1)
  renderer.render(pass, time or 0, self.width, self.height)
end

function Surface:composite(pass, x, y, width, height)
  pass:setColor(1, 1, 1, 1)
  pass:draw(self.texture, x + width / 2, y + height / 2, 0, width)
end

return Surface
