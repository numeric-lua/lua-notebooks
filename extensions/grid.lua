--
-- A small interactive 3D grid extension used to exercise discovery, pointer
-- routing, and keyboard focus independently of the cube.
--
local Grid = {
  id = "grid",
  version = 1,
  title = "Density grid",
}

function Grid.render(pass, time, width, height, state)
  state.yaw = state.yaw or 0.7
  state.pitch = state.pitch or 0.5
  state.distance = state.distance or 7
  local step = state.dense and 1 or 2
  local extent = 8

  local cos_pitch = math.cos(state.pitch)
  local eye = vec3(
    state.distance * cos_pitch * math.sin(state.yaw),
    state.distance * math.sin(state.pitch),
    state.distance * cos_pitch * math.cos(state.yaw))

  pass:setProjection(1, mat4():perspective(math.rad(55),
    math.max(0.01, width / height), 0.1, 100))
  pass:setViewPose(1, mat4():lookAt(eye, vec3(0, 0, 0)), true)
  pass:setDepthTest("lequal")
  for x = -extent, extent, step do
    pass:setColor(0.2, 0.35, 0.55, 1)
    pass:line(x, -1.5, -extent, x, -1.5, extent)
  end
  for z = -extent, extent, step do
    pass:setColor(0.25, 0.5, 0.65, 1)
    pass:line(-extent, -1.5, z, extent, -1.5, z)
  end
  pass:setColor(0.95, 0.55, 0.3, 1)
  pass:cube(0, -1.2, 0, 0.7, time or 0, 0, 1, 0)
  pass:setDepthTest()
end

function Grid.pointer(state, event)
  if event.type == "down" then
    state.dragging = true
  elseif event.type == "up" then
    state.dragging = false
  elseif event.type == "move" and state.dragging then
    state.yaw = (state.yaw or 0.7) + (event.dx or 0) * 0.008
    state.pitch = math.max(-1.3, math.min(1.3,
      (state.pitch or 0.5) + (event.dy or 0) * 0.008))
  elseif event.type == "wheel" then
    state.distance = math.max(3, math.min(20,
      (state.distance or 7) + (event.dy or 0) * 0.6))
  end
end

function Grid.key(state, event)
  if event.key == "space" and event.pressed then
    state.dense = not state.dense
  end
end

function Grid.resize(state, width, height)
  state.width = width
  state.height = height
end

return Grid
