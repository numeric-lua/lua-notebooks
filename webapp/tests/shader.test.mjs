import test from "node:test";
import assert from "node:assert/strict";
import { selectShaderPreset, shaderFallbackMessage } from "../js/shader.js";

test("selects the built-in star_nest preset", () => {
  const preset = selectShaderPreset("star_nest");
  assert.ok(preset);
  assert.equal(preset.name, "star_nest");
  assert.match(preset.fragmentSource, /uniform float time;/);
  assert.match(preset.fragmentSource, /gl_FragColor/);
});

test("unknown presets fall back to a clear message", () => {
  assert.equal(selectShaderPreset("supernova"), null);
  let message;
  assert.doesNotThrow(() => { message = shaderFallbackMessage("supernova"); });
  assert.match(message, /Unknown shader "supernova"/);
  assert.match(message, /star_nest/);
  assert.match(message, /LÖVR desktop host/);
});

test("inline shader source falls back without being echoed", () => {
  const message = shaderFallbackMessage("vec4 lovrmain() {\n  return vec4(1.0);\n}");
  assert.match(message, /Unknown shader source/);
  assert.doesNotMatch(message, /lovrmain/);
});

test("missing or non-string shader names do not throw", () => {
  assert.equal(selectShaderPreset(undefined), null);
  assert.equal(selectShaderPreset(42), null);
  assert.match(shaderFallbackMessage(undefined), /Unknown shader source/);
});
