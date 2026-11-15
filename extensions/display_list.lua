--
-- Declarative display-list extensions (T1).  User JSON is data only; the host
-- validates every command and replays it with fixed primitives.
--
local DisplayList = {}

local OPS = { color = true, clear = true, cube = true, line = true,
  plane = true, depth = true, camera = true, material = true }

local function finite(value)
  return type(value) == "number" and value == value and
    value ~= math.huge and value ~= -math.huge
end

local function color(value, path)
  if type(value) ~= "table" or #value < 3 or #value > 4 then
    return nil, path .. " must be an rgb(a) list"
  end
  for index = 1, #value do
    if not finite(value[index]) or value[index] < 0 or value[index] > 1 then
      return nil, path .. " color out of range"
    end
  end
  return true
end

function DisplayList.validate(descriptor, source)
  source = source or "display extension"
  if type(descriptor) ~= "table" then return nil, source .. ": not a table" end
  if type(descriptor.id) ~= "string" or
     not descriptor.id:match("^[a-z][a-z0-9_-]*$") then
    return nil, source .. ": invalid id"
  end
  local display = descriptor.display
  if type(display) ~= "table" or type(display.commands) ~= "table" then
    return nil, source .. ": display.commands is required"
  end
  if #display.commands > 4096 then
    return nil, source .. ": too many commands"
  end
  if display.clear ~= nil then
    local ok, err = color(display.clear, "clear")
    if not ok then return nil, source .. ": " .. err end
  end
  for index, command in ipairs(display.commands) do
    if type(command) ~= "table" or not OPS[command.op] then
      return nil, source .. ": invalid op at " .. index
    end
    if command.op == "color" then
      local ok, err = color(command.rgba, "color")
      if not ok then return nil, source .. ": " .. err end
    elseif command.op == "cube" then
      if not finite(command.x) or not finite(command.y) or
         not finite(command.z) or not finite(command.size) or
         command.size <= 0 or command.size > 1e5 then
        return nil, source .. ": invalid cube at " .. index
      end
    elseif command.op == "line" or command.op == "plane" then
      for _, field in ipairs({ "x", "y", "z", "w", "h" }) do
        if command[field] ~= nil and not finite(command[field]) then
          return nil, source .. ": invalid " .. field .. " at " .. index
        end
      end
    elseif command.op == "camera" then
      if type(command.eye) ~= "table" or type(command.target) ~= "table" then
        return nil, source .. ": camera needs eye/target"
      end
    elseif command.op == "depth" then
      if command.mode ~= "none" and command.mode ~= "gequal" and
         command.mode ~= "lequal" then
        return nil, source .. ": invalid depth mode"
      end
    elseif command.op == "material" then
      if command.name ~= "lit" and command.name ~= "unlit" then
        return nil, source .. ": invalid material"
      end
    end
  end
  descriptor.version = descriptor.version or 1
  descriptor.title = descriptor.title or descriptor.id
  descriptor.tier = "declarative"
  return descriptor
end

function DisplayList.replay(pass, descriptor, width, height)
  local display = descriptor.display
  if display.clear then
    local c = display.clear
    pass:setClear(c[1], c[2], c[3], c[4] or 1)
  end
  for _, command in ipairs(display.commands) do
    if command.op == "color" then
      local c = command.rgba
      pass:setColor(c[1], c[2], c[3], c[4] or 1)
    elseif command.op == "cube" then
      pass:cube(command.x, command.y, command.z, command.size or 1,
        command.angle or 0, command.ax or 0, command.ay or 1, command.az or 0)
    elseif command.op == "line" then
      pass:line(command.x1 or 0, command.y1 or 0, command.z1 or 0,
        command.x2 or 1, command.y2 or 0, command.z2 or 0)
    elseif command.op == "plane" then
      pass:plane(command.x or 0, command.y or 0, command.z or 0,
        command.w or 1, command.h or 1)
    elseif command.op == "depth" then
      pass:setDepthTest(command.mode == "none" and nil or command.mode)
    elseif command.op == "camera" then
      local eye, target = command.eye, command.target
      local fov = command.fov or math.rad(55)
      pass:setProjection(1, mat4():perspective(fov,
        command.aspect or width / height, command.near or 0.1,
        command.far or 100))
      pass:setViewPose(1, mat4():lookAt(vec3(eye[1], eye[2], eye[3]),
        vec3(target[1], target[2], target[3])), true)
    elseif command.op == "material" then
      if command.name == "lit" then
        pass:setShader(require("ui.shading").lit())
      else
        pass:setShader()
      end
    end
  end
  pass:setDepthTest()
  pass:setShader()
end

return DisplayList
