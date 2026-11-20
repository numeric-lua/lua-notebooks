--
-- Host-side shader widgets.  Fragment shaders receive a `time` uniform and
-- draw into a clipped rectangle on the notebook canvas.
--
local Shader = {}
local cache = {}

local STAR_NEST = [=[
// Star Nest by Pablo Román Andrioli
// This content is under the MIT License.
Constants {
  float time;
};
vec4 lovrmain() {
  vec2 res = vec2(1.78, 1.0);
  vec2 uv = UV * res - 0.5;
  vec3 dir = vec3(uv * 0.8, 1.0);
  float t = time * 0.01 + 0.25;
  float a1 = 0.5;
  float a2 = 0.8;
  mat2 rot1 = mat2(cos(a1), sin(a1), -sin(a1), cos(a1));
  mat2 rot2 = mat2(cos(a2), sin(a2), -sin(a2), cos(a2));
  dir.xz *= rot1;
  dir.xy *= rot2;
  vec3 from = vec3(1.0, 0.5, 0.5);
  from += vec3(0.0, t, -2.0);
  from.xz *= rot1;
  from.xy *= rot2;
  float s = 0.1;
  float fade = 1.0;
  vec3 v = vec3(0.0);
  for (int r = 0; r < 20; r++) {
    vec3 p = from + s * dir * 0.5;
    p = abs(vec3(0.85) - mod(p, vec3(1.7)));
    float pa = 0.0;
    float a = 0.0;
    for (int i = 0; i < 17; i++) {
      p = abs(p) / dot(p, p) - 0.53;
      a += abs(length(p) - pa);
      pa = length(p);
    }
    float dm = max(0.0, 0.3 - a * a * 0.001);
    a *= a * a;
    if (r > 6) fade *= 1.0 - dm;
    v += fade;
    v += vec3(s, s * s, s * s * s * s) * a * 0.0015 * fade;
    fade *= 0.73;
    s += 0.1;
  }
  v = mix(vec3(length(v)), v, 0.85);
  return vec4(v * 0.01, length(v) * 0.25);
}
]=]

local PRESETS = { star_nest = STAR_NEST }

function Shader.get(source)
  if source == nil then return nil, "missing shader source" end
  local key = source
  if PRESETS[source] then key = "preset:" .. source; source = PRESETS[source] end
  if cache[key] then return cache[key] end
  local ok, shader = pcall(lovr.graphics.newShader, "unlit", source)
  if not ok then
    return nil, tostring(shader)
  end
  cache[key] = shader
  return shader
end

function Shader.draw(pass, spec, time, x, y, width, height, scale)
  local shader, err = Shader.get(spec.shader)
  if shader == nil then
    pass:setColor(1, 0.4, 0.4, 1)
    pass:setFont(lovr.graphics.getDefaultFont())
    pass:text("shader: " .. tostring(err), x + 8, y + 8, 0, 0.8,
      0, 0, 1, 0, 0, "left", "top")
    return
  end
  pass:setShader(shader)
  pass:send("time", time or 0)
  pass:setColor(1, 1, 1, 1)
  scale = scale or 1
  if x + width <= 0 or y + height <= 0 or width <= 0 or height <= 0 then
    return
  end
  local scissor_x = math.max(0, x * scale)
  local scissor_y = math.max(0, y * scale)
  local scissor_w = math.max(1, width * scale - (scissor_x - x * scale))
  local scissor_h = math.max(1, height * scale - (scissor_y - y * scale))
  pass:setScissor(scissor_x, scissor_y, scissor_w, scissor_h)
  pass:plane(x + width / 2, y + height / 2, 0, width, height)
  pass:setScissor()
  pass:setShader()
end

return Shader
