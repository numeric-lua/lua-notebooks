--
-- Tiny unlit-plus-directional fragment shader for primitive extensions.
--
local Shading = {}
local shader

function Shading.lit()
  if shader == nil then
    shader = lovr.graphics.newShader("unlit", [[
      vec4 lovrmain() {
        vec3 n = normalize(Normal);
        float light = max(dot(n, normalize(vec3(0.35, 0.8, 0.5))), 0.0);
        return Color * (0.35 + 0.65 * light);
      }
    ]])
  end
  return shader
end

return Shading
