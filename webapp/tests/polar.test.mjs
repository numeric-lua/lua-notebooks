import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  BAR_SAMPLE_LIMIT, DEFAULT_POINT_RADIUS, LINE_SAMPLE_LIMIT, PALETTE,
  RADIUS_LABEL_LIMIT, SCATTER_SAMPLE_LIMIT, THETA_LABEL_LIMIT,
  barSectors, finiteNumber, frameRadius, pointRadius, polarConfig,
  polarRings, polarSpokes, projectPolar, radiusLabel, resolvePolar,
  sampleStep, thetaLabel, validColor,
} from "../js/polar.js";
import { polarFallbackScene, polarScene } from "./fixtures.js";

function near(actual, expected, tolerance = 1e-9, label = "value") {
  assert.ok(Math.abs(actual - expected) <= tolerance,
    `${label}: expected ${expected}, got ${actual}`);
}

test("resolves options, palette, and observed rmax", () => {
  const resolved = resolvePolar(polarScene());
  assert.equal(resolved.rmax, 2);
  assert.equal(resolved.thetaZero, 0);
  assert.equal(resolved.direction, 1);
  assert.equal(resolved.series.length, 3);
  assert.equal(resolved.series[0].kind, "line");
  assert.equal(resolved.series[0].color, "#1f77b4");
  assert.equal(resolved.series[1].points[0].radius, 5);
  assert.equal(resolved.series[2].bars[0].color, "#2ca02c");

  const fallback = {
    type: "luaplotlib", orientation: "polar",
    polar: {
      series: [
        { kind: "line", theta: [0], r: [-3] },
        { kind: "line", theta: [0], r: [2] },
      ],
    },
  };
  const auto = resolvePolar(fallback);
  assert.equal(auto.rmax, 3);
  assert.equal(auto.series[0].color, PALETTE[0]);
  assert.equal(auto.series[1].color, PALETTE[1]);
});

test("handles missing and malformed polar options", () => {
  const config = polarConfig({});
  assert.equal(config.rmax, null);
  assert.equal(config.thetaZero, 0);
  assert.equal(config.direction, 1);
  assert.deepEqual(config.polar, {});

  const bad = resolvePolar({
    type: "luaplotlib", orientation: "polar",
    polar: {
      rmax: -2, theta_zero: 1 / 0, theta_direction: "sideways",
      series: [{ kind: "line", theta: [0, 1 / 0], r: [1, 2] }],
    },
  });
  assert.equal(bad.rmax, 1);
  assert.equal(bad.thetaZero, 0);
  assert.equal(bad.direction, 1);
  assert.equal(bad.series[0].points.length, 1);
});

test("projects screen coordinates and clamps out-of-range radii", () => {
  let point = projectPolar(100, 100, 40, 2, 0, 1, 0, 1);
  near(point.x, 120); near(point.y, 100); near(point.angle, 0);
  point = projectPolar(100, 100, 40, 2, 0, 1, Math.PI / 2, 1);
  near(point.x, 100); near(point.y, 80);
  point = projectPolar(100, 100, 40, 2, 0, 1, 0, 99);
  near(point.x, 140); near(point.y, 100);
  point = projectPolar(100, 100, 40, 2, 0, -1, Math.PI / 2, 1);
  near(point.x, 100); near(point.y, 120);
  point = projectPolar(100, 100, 40, 2, Math.PI / 2, -1, 0, -99);
  near(point.x, 100); near(point.y, 140);
});

test("filters ticks and omits long labels", () => {
  const polar = {
    r_ticks: [
      { value: 0, label: "zero" },
      { value: 1, label: "1" },
      { value: 3, label: "3" },
      { value: 2, label: "x".repeat(RADIUS_LABEL_LIMIT + 1) },
      { value: 1.5, label: "x".repeat(RADIUS_LABEL_LIMIT) },
    ],
    theta_ticks: [
      { value: 0, label: "y".repeat(THETA_LABEL_LIMIT + 1) },
      { value: Math.PI, label: "180" },
      { value: Math.PI / 2 },
    ],
  };
  const rings = polarRings(polar, 2);
  assert.equal(rings.length, 3);
  assert.equal(radiusLabel(rings[0]), "1");
  assert.equal(radiusLabel(rings[1]), null);
  assert.equal(radiusLabel(rings[2]), "x".repeat(RADIUS_LABEL_LIMIT));
  assert.equal(radiusLabel({ value: 1.5 }), "1.5");

  const spokes = polarSpokes(polar);
  assert.equal(spokes.length, 3);
  assert.equal(thetaLabel(spokes[0]), null);
  assert.equal(thetaLabel(spokes[1]), "180");
  assert.equal(thetaLabel(spokes[2]), "90°");

  const fallbackRings = polarRings({}, 2);
  assert.equal(fallbackRings.length, 4);
  assert.equal(radiusLabel(fallbackRings[0]), "0.5");
  const fallbackSpokes = polarSpokes({});
  assert.equal(fallbackSpokes.length, 12);
  assert.equal(thetaLabel(fallbackSpokes[1]), "30°");

  assert.equal(radiusLabel({ value: 3, label: "" }), "3");
  assert.equal(thetaLabel({ value: Math.PI, label: "" }), "180°");
  assert.equal(radiusLabel(null), null);
});

test("splits wide bars, rotates negative radii, and clamps", () => {
  const full = barSectors({ theta: 0, r: 1, width: 7 }, 100, 2, 0, 1);
  assert.equal(full.length, 1);
  assert.equal(full[0].full, true);
  near(full[0].radius, 50);

  const wide = barSectors({ theta: 0, r: 1, width: 3.5 }, 100, 2, 0, 1);
  assert.equal(wide.length, 2);
  near(wide[0].startAngle, -1.75);
  near(wide[1].endAngle, 1.75);

  const negative = barSectors({ theta: 0, r: -1, width: 0.2 }, 100, 2, 0, 1);
  assert.equal(negative.length, 1);
  near(negative[0].startAngle, Math.PI - 0.1);

  const clamped = barSectors({ theta: 0, r: 100, width: 0.2 }, 100, 2, 0, 1);
  near(clamped[0].radius, 100);

  const clockwise = barSectors({ theta: 0, r: 1, width: 0.2 }, 100, 2, 0, -1);
  near(clockwise[0].startAngle, 0.1);
  near(clockwise[0].endAngle, -0.1);

  assert.deepEqual(barSectors({ theta: 0, r: 0, width: 0.2 }, 100, 2, 0, 1), []);
  assert.deepEqual(barSectors({ theta: 0, r: 1, width: 0 }, 100, 2, 0, 1), []);
  assert.deepEqual(barSectors(null, 100, 2, 0, 1), []);
});

test("samples long series with the documented caps", () => {
  assert.equal(sampleStep(0), 1);
  assert.equal(sampleStep(96, LINE_SAMPLE_LIMIT), 1);
  assert.equal(sampleStep(1600, LINE_SAMPLE_LIMIT), 2);
  assert.equal(sampleStep(401, SCATTER_SAMPLE_LIMIT), 2);
  assert.equal(sampleStep(1201, BAR_SAMPLE_LIMIT), 4);
});

test("clamps points, colors, and frame radius", () => {
  assert.equal(frameRadius(496, 166), 73);
  assert.equal(frameRadius(1, 1), 1);
  assert.equal(pointRadius({ radius: 100 }), 8);
  assert.equal(pointRadius({ radius: -5 }), 1);
  assert.equal(pointRadius({}), DEFAULT_POINT_RADIUS);
  assert.equal(pointRadius(null), DEFAULT_POINT_RADIUS);

  assert.equal(validColor("#abc"), "#abc");
  assert.equal(validColor("#aabbcc"), "#aabbcc");
  assert.equal(validColor("red"), null);
  assert.equal(validColor("#12345"), null);
  assert.equal(finiteNumber(0), true);
  assert.equal(finiteNumber(Number.NaN), false);
  assert.equal(finiteNumber("1"), false);
});

test("fallback scene resolves auto rmax and negative radii", () => {
  const resolved = resolvePolar(polarFallbackScene());
  assert.equal(resolved.rmax, 2.5);
  assert.equal(resolved.direction, -1);
  const point = projectPolar(0, 0, 100, resolved.rmax, 0, resolved.direction, Math.PI, -2.5);
  near(point.x, 100);
  near(point.y, 0, 1e-9);
});

// tests/polar.lua reads the same fixture and asserts the same numbers with the
// shared Lua module.  A change on either side that breaks renderer parity
// fails one of the two suites.
test("matches the cross-renderer polar fixture", () => {
  const fixture = JSON.parse(readFileSync(
    new URL("./fixtures/polar-parity.json", import.meta.url), "utf8"));
  const resolved = resolvePolar(fixture.scene);
  const expected = fixture.expected;
  assert.equal(resolved.rmax, expected.rmax);
  assert.equal(resolved.observed, expected.observed);
  assert.equal(resolved.direction, expected.direction);
  assert.deepEqual(resolved.series.map((series) => series.kind),
    expected.series_kinds);

  const { cx, cy, radius } = fixture.layout;
  assert.equal(frameRadius(fixture.layout.width - 104,
    fixture.layout.height - 64), radius);
  for (const projection of expected.projection) {
    const point = projectPolar(cx, cy, radius, resolved.rmax,
      resolved.thetaZero, resolved.direction, projection.theta, projection.r);
    near(point.x, projection.x, 1e-9, "projection x");
    near(point.y, projection.y, 1e-9, "projection y");
    near(point.angle, projection.angle, 1e-9, "projection angle");
  }

  const rings = polarRings(resolved.polar, resolved.rmax);
  assert.deepEqual(rings.map(radiusLabel), expected.radius_labels);
  const spokes = polarSpokes(resolved.polar);
  assert.deepEqual(spokes.map(thetaLabel), expected.theta_labels);

  const sectors = barSectors(resolved.series[1].bars[0], radius,
    resolved.rmax, resolved.thetaZero, resolved.direction);
  assert.equal(sectors.length, 1);
  near(sectors[0].radius, expected.bar_sector.radius, 1e-9, "sector radius");
  near(sectors[0].startAngle, expected.bar_sector.start_angle, 1e-9, "sector start");
  near(sectors[0].endAngle, expected.bar_sector.end_angle, 1e-9, "sector end");
});

