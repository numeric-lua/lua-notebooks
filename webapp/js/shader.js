// Browser-side shader previews.
//
// The kernel only sends plain widget specs.  This module owns the host-side
// rendering, so no WebGL or graphics objects ever reach the kernel.  The
// built-in Star Nest preset is adapted from the same MIT-licensed source used
// by ui/shader.lua, translated from LÖVR shader syntax to WebGL GLSL.

const STAR_NEST_FRAGMENT = `precision highp float;

uniform float time;
uniform vec2 resolution;

void main() {
  vec2 res = vec2(resolution.x / resolution.y, 1.0);
  vec2 uv = gl_FragCoord.xy / resolution * res - 0.5;
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
  gl_FragColor = vec4(v * 0.01, 1.0);
}
`;

const VERTEX_SHADER = `attribute vec2 aPosition;

void main() {
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
`;

const PRESETS = Object.freeze({
  star_nest: Object.freeze({
    name: "star_nest",
    title: "Star Nest",
    fragmentSource: STAR_NEST_FRAGMENT,
  }),
});

export function selectShaderPreset(source) {
  if (typeof source !== "string") return null;
  return Object.prototype.hasOwnProperty.call(PRESETS, source) ? PRESETS[source] : null;
}

export function shaderFallbackMessage(source) {
  const value = typeof source === "string" ? source.trim() : "";
  const identifier = value && !/\s/.test(value) && value.length <= 64 ? `"${value}"` : "source";
  return `Unknown shader ${identifier}; the browser preview supports only the star_nest preset. ` +
    "Use the LÖVR desktop host for other shaders.";
}

function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  if (!shader) return null;
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    gl.deleteShader(shader);
    return null;
  }
  return shader;
}

function createProgram(gl, preset) {
  const vertex = compileShader(gl, gl.VERTEX_SHADER, VERTEX_SHADER);
  const fragment = compileShader(gl, gl.FRAGMENT_SHADER, preset.fragmentSource);
  if (!vertex || !fragment) {
    if (vertex) gl.deleteShader(vertex);
    if (fragment) gl.deleteShader(fragment);
    return null;
  }
  const program = gl.createProgram();
  if (!program) {
    gl.deleteShader(vertex);
    gl.deleteShader(fragment);
    return null;
  }
  gl.attachShader(program, vertex);
  gl.attachShader(program, fragment);
  gl.linkProgram(program);
  gl.deleteShader(vertex);
  gl.deleteShader(fragment);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    gl.deleteProgram(program);
    return null;
  }
  return program;
}

function createRenderer(canvas, preset) {
  const gl = canvas.getContext("webgl", {
    alpha: false,
    antialias: false,
    depth: false,
    stencil: false,
    powerPreference: "low-power",
  }) || canvas.getContext("experimental-webgl", {
    alpha: false,
    antialias: false,
    depth: false,
    stencil: false,
  });
  if (!gl) throw new Error("WebGL is not available");

  const program = createProgram(gl, preset);
  if (!program) throw new Error("the shader could not be compiled");

  const buffer = gl.createBuffer();
  if (!buffer) throw new Error("WebGL could not create a vertex buffer");
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(
    gl.ARRAY_BUFFER,
    new Float32Array([-1, -1, 3, -1, -1, 3]),
    gl.STATIC_DRAW,
  );

  const position = gl.getAttribLocation(program, "aPosition");
  const timeUniform = gl.getUniformLocation(program, "time");
  const resolutionUniform = gl.getUniformLocation(program, "resolution");
  gl.useProgram(program);
  gl.enableVertexAttribArray(position);
  gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
  gl.disable(gl.DEPTH_TEST);
  gl.disable(gl.BLEND);

  let frame = 0;
  let startedAt = 0;

  const stop = () => {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
  };

  const resize = () => {
    const rect = canvas.getBoundingClientRect();
    const dpr = Math.min(globalThis.devicePixelRatio || 1, 1.5);
    const width = Math.max(1, Math.round((rect.width || 320) * dpr));
    const height = Math.max(1, Math.round((rect.height || 180) * dpr));
    if (canvas.width !== width || canvas.height !== height) {
      canvas.width = width;
      canvas.height = height;
    }
    return { width, height };
  };

  const draw = (now) => {
    if (!canvas.isConnected) {
      stop();
      return;
    }
    if (!startedAt) startedAt = now;
    const { width, height } = resize();
    gl.viewport(0, 0, width, height);
    gl.clearColor(0.04, 0.05, 0.08, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.useProgram(program);
    gl.uniform1f(timeUniform, (now - startedAt) / 1000);
    gl.uniform2f(resolutionUniform, width, height);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    frame = requestAnimationFrame(draw);
  };

  canvas._shaderStop = stop;
  frame = requestAnimationFrame(draw);
  return stop;
}

function fallback(container, text) {
  const message = document.createElement("div");
  message.className = "widget-shader-message";
  message.textContent = text;
  container.replaceChildren(message);
}

export function renderShaderWidget(container, spec = {}) {
  const preset = selectShaderPreset(spec.shader);
  if (!preset) {
    fallback(container, `${spec.label || "shader"} · ${shaderFallbackMessage(spec.shader)}`);
    return null;
  }

  const height = Number.isFinite(spec.height) && spec.height > 0 ? spec.height : 180;
  const canvas = document.createElement("canvas");
  canvas.className = "widget-shader-canvas";
  canvas.style.height = `${height}px`;
  canvas.setAttribute("role", "img");
  canvas.setAttribute("aria-label", `${spec.label || preset.title} shader preview`);

  const caption = document.createElement("div");
  caption.className = "widget-shader-caption";
  const label = document.createElement("span");
  label.textContent = spec.label || preset.title;
  const meta = document.createElement("span");
  meta.textContent = `${preset.name} · WebGL`;
  caption.append(label, meta);

  container.replaceChildren(canvas, caption);
  try {
    createRenderer(canvas, preset);
  } catch (error) {
    fallback(container, `${spec.label || "shader"} · shader preview unavailable: ${error?.message || "WebGL could not start"}`);
    return null;
  }
  return canvas;
}

export function stopShaderWidgets(root = document) {
  root.querySelectorAll(".widget-shader-canvas").forEach((canvas) => {
    canvas._shaderStop?.();
    delete canvas._shaderStop;
  });
}
