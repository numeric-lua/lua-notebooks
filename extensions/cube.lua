--
-- Built-in cube extension.  The host gives it a Pass that targets an offscreen
-- Texture; it must not create windows or touch notebook UI state.
--
local Cube = {}

function Cube.render(pass, time, width, height)
  pass:setProjection(1, mat4():perspective(math.rad(55),
    math.max(0.01, width / height), 0.1, 100))
  pass:setViewPose(1, mat4():lookAt(vec3(2.4, 2.0, 3.2), vec3(0, 0, 0)), true)
  pass:setDepthTest("lequal")
  pass:setColor(0.95, 0.55, 0.3, 1)
  pass:cube(0, 0, 0, 1, time, 0, 1, 0)
  pass:setColor(0.25, 0.55, 0.9, 1)
  pass:cube(0, -1.15, 0, 0.8, -time, 0, 1, 0)
  pass:setDepthTest()
end

return Cube
