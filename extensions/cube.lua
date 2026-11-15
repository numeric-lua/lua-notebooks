--
-- Built-in interactive cube extension.  The host gives it a Pass that targets
-- an offscreen Texture and a small state table for orbit input.
--
local Cube = {}

function Cube.render(pass, time, width, height, state)
  state = state or {}
  state.yaw = state.yaw or 0.6
  state.pitch = state.pitch or 0.3
  state.distance = state.distance or 4.2

  local cos_pitch = math.cos(state.pitch)
  local eye = vec3(
    state.distance * cos_pitch * math.sin(state.yaw),
    state.distance * math.sin(state.pitch),
    state.distance * cos_pitch * math.cos(state.yaw))

  pass:setProjection(1, mat4():perspective(math.rad(55),
    math.max(0.01, width / height), 0.1, 100))
  pass:setViewPose(1, mat4():lookAt(eye, vec3(0, 0, 0)), true)
  pass:setDepthTest("lequal")
  pass:setColor(0.95, 0.55, 0.3, 1)
  pass:cube(0, 0, 0, 1, time or 0, 0, 1, 0)
  pass:setColor(0.25, 0.55, 0.9, 1)
  pass:cube(0, -1.15, 0, 0.8, -(time or 0), 0, 1, 0)
  pass:setDepthTest()
end

return Cube
