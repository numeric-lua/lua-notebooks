import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  BAR_SAMPLE_LIMIT, COLORBAR_STEPS, DEFAULT_POINT_RADIUS, FULL_TURN_PARTS,
  HEATMAP_CELL_LIMIT, LINE_SAMPLE_LIMIT, PALETTE, QUIVER_AUTO_LENGTH,
  QUIVER_DEFAULT_MAX_ARROWS, QUIVER_MAX_ARROWS, RADIUS_LABEL_LIMIT,
  SCATTER_SAMPLE_LIMIT, THETA_LABEL_LIMIT, barSectors, colorbarLayout,
  colorbarSteps, colorbarTicks, collectColorbar, collectContours,
  collectHeatmaps, compactNumber, contourLabel, contourSegmentPoints,
  finiteNumber, frameLayout, frameRadius, heatColor, heatmapCells,
  heatmapSampling, pointRadius, polarConfig, polarRings, polarSpokes,
  projectPolar, quiverArrows, radiusLabel, resolvePolar, sampleStep,
  thetaLabel, validColor,
} from "../js/polar.js";
import {
  largeFieldValues, largePolarFieldScene, polarFallbackScene,
  polarFieldScene, polarScene,
} from "./fixtures.js";

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


test("maps field values through the shared viridis palette", () => {
  assert.equal(heatColor(0, 0, 5), "#440154");
  assert.equal(heatColor(5, 0, 5), "#fde725");
  assert.equal(heatColor(1, 0, 5), "#345382");
  assert.equal(heatColor(-1, 0, 5), "#440154");
  assert.equal(heatColor(9, 0, 5), "#fde725");
  assert.equal(heatColor(0, 0, 0), "#440154");
  assert.equal(compactNumber(0), "0");
  assert.equal(compactNumber(2.5), "2.5");
  assert.equal(compactNumber(1234), "1230");
  assert.equal(compactNumber(0.0001), "0.0001");
  assert.equal(compactNumber(0.00001), "1e-5");
  assert.equal(compactNumber(1 / 0), null);

  const heatmaps = collectHeatmaps({
    heatmaps: [
      { rows: 2, cols: 2, values: [[1, 2], [3, 4]] },
      { rows: "bad", cols: 2, values: [] },
    ],
  });
  assert.equal(heatmaps.length, 1);
  assert.equal(heatmaps[0].vmin, 1);
  assert.equal(heatmaps[0].vmax, 4);
  assert.equal(heatmaps[0].rmin, 0);
  assert.equal(heatmaps[0].rmax, 2);
  assert.equal(heatmaps[0].thetaMax, 2 * Math.PI);
  assert.equal(heatmaps[0].alpha, 1);
  const contours = collectContours({
    contours: [
      {
        levels: [{ level: 2, segments: [[0, 1, 1, 2], [1]] }],
        labels: true, style: { color: "#112233" },
      },
      { levels: [] },
    ],
  });
  assert.equal(contours.length, 1);
  assert.equal(contours[0].levels[0].segments.length, 1);
  assert.equal(contours[0].style.color, "#112233");
  assert.equal(contours[0].style.linestyle, "solid");
  assert.equal(collectColorbar({}, []), null);
});

test("derives and tolerates malformed field metadata", () => {
  const derived = resolvePolar({
    type: "luaplotlib", orientation: "polar",
    polar: {
      heatmaps: [{
        rows: 1, cols: 1, values: [[0.5]], vmin: 0, vmax: 1,
        colorbar: true,
      }],
    },
  });
  assert.ok(derived.colorbar);
  assert.equal(derived.colorbar.ticks.length, 3);
  assert.equal(colorbarTicks(derived.colorbar)[1].label, "0.5");

  const scene = {
    type: "luaplotlib", orientation: "polar",
    polar: {
      rmax: 2,
      heatmaps: [{
        rows: 2, cols: 2,
        values: [[1 / 0, 2], [3, 0 / 0]],
        vmin: 0, vmax: 0, alpha: 2,
      }],
      contours: [{
        levels: [{ level: 1, segments: [[0, 0, 0 / 0, 1], [1, 2, 3, 4]] }],
        labels: true,
      }],
      colorbar: { vmin: 0, vmax: 0 },
    },
  };
  const resolved = resolvePolar(scene);
  assert.equal(resolved.heatmaps.length, 1);
  assert.equal(resolved.heatmaps[0].vmax, 1);
  assert.equal(resolved.heatmaps[0].alpha, 1);
  assert.equal(resolved.colorbar, null);
  assert.equal(resolved.contours[0].levels[0].segments.length, 1);
  const cells = heatmapCells(resolved.heatmaps[0], 100, 100, 50,
    resolved.rmax, 0, 1);
  assert.equal(cells.length, 4);
  for (const cell of cells) assert.match(cell.color, /^#[0-9a-f]{6}$/);
});

test("projects heatmap cells, contour edges, and the colorbar", () => {
  const heatmap = {
    rows: 2, cols: 3, values: [[0, 1, 2], [3, 4, 5]],
    vmin: 0, vmax: 5, rmin: 0.5, rmax: 2,
    thetaMin: 0, thetaMax: Math.PI, alpha: 0.9,
  };
  const { cx, cy, radius } = frameLayout(52, 34, 548, 200, true);
  near(cx, 272); near(cy, 117); near(radius, 73);
  const cells = heatmapCells(heatmap, cx, cy, radius, 2, 0, 1);
  assert.equal(cells.length, 6);
  assert.equal(cells[0].color, "#440154");
  assert.equal(cells[5].color, "#fde725");
  near(cells[0].innerRadius, 18.25);
  near(cells[0].outerRadius, 45.625);
  near(cells[0].startAngle, 0);
  near(cells[0].endAngle, Math.PI / 3);
  near(cells[4].innerRadius, 45.625);
  near(cells[4].outerRadius, 73);

  const full = {
    rows: 1, cols: 1, values: [[1]], vmin: 0, vmax: 1,
    rmin: 0.5, rmax: 1, thetaMin: 0, thetaMax: 2 * Math.PI, alpha: 1,
  };
  const ring = heatmapCells(full, 100, 100, 50, 1, 0, 1);
  assert.equal(ring.length, 1);
  assert.equal(ring[0].parts.length, FULL_TURN_PARTS);
  full.rmin = 0;
  assert.equal(heatmapCells(full, 100, 100, 50, 1, 0, 1)[0].fullDisc, true);

  const contour = { rmin: 0, rmax: 2 };
  const points = contourSegmentPoints(contour, [0, 0.5, Math.PI / 2, 1.5],
    cx, cy, radius, 2, 0, 1);
  assert.equal(points.length, 25);
  near(points[0].x, 290.25);
  near(points[0].y, 117);
  near(points[24].x, 272);
  near(points[24].y, 62.25);

  const bar = { vmin: 0, vmax: 5, ticks: [0, 2.5, 5] };
  const geometry = colorbarLayout(cx, cy, radius);
  near(geometry.x, 361); near(geometry.y, 54.95);
  near(geometry.width, 16); near(geometry.height, 124.1);
  const ticks = colorbarTicks(bar);
  assert.deepEqual(ticks.map((tick) => tick.label), ["0", "2.5", "5"]);
  near(ticks[2].fraction, 1);
  const steps = colorbarSteps(bar);
  assert.equal(steps.length, COLORBAR_STEPS);
  assert.equal(steps[0].y0, 0);
  assert.equal(steps[COLORBAR_STEPS - 1].y1, 1);
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

test("matches the cross-renderer polar field fixture", () => {
  const fixture = JSON.parse(readFileSync(
    new URL("./fixtures/polar-parity.json", import.meta.url), "utf8"));
  const scene = fixture.field_scene;
  assert.deepEqual(polarFieldScene(), scene);
  const expected = fixture.field_expected;
  const resolved = resolvePolar(scene);
  assert.equal(resolved.rmax, expected.rmax);
  assert.equal(resolved.observed, expected.observed);

  const layout = fixture.field_layout;
  const { cx, cy, radius } = frameLayout(52, 34, layout.width - 52,
    layout.height - 30, layout.has_colorbar);
  assert.equal(cx, layout.cx);
  assert.equal(cy, layout.cy);
  assert.equal(radius, layout.radius);

  const cells = heatmapCells(resolved.heatmaps[0], cx, cy, radius,
    resolved.rmax, resolved.thetaZero, resolved.direction);
  assert.equal(cells.length, expected.heatmap_cells);
  assert.deepEqual(cells.map((cell) => cell.color), expected.heat_colors);
  near(cells[0].innerRadius, expected.first_cell.inner_radius);
  near(cells[0].outerRadius, expected.first_cell.outer_radius);
  near(cells[0].startAngle, expected.first_cell.start_angle);
  near(cells[0].endAngle, expected.first_cell.end_angle);

  const contour = resolved.contours[0];
  contour.levels[0].segments.forEach((segment, index) => {
    const points = contourSegmentPoints(contour, segment, cx, cy, radius,
      resolved.rmax, resolved.thetaZero, resolved.direction);
    assert.equal(points.length, expected.contour_point_counts[index]);
    if (index === 0) {
      near(points[0].x, expected.contour_first.x);
      near(points[0].y, expected.contour_first.y);
    } else {
      near(points[points.length - 1].x, expected.contour_second_last.x);
      near(points[points.length - 1].y, expected.contour_second_last.y);
    }
  });
  const label = contourLabel(contour, contour.levels[0], cx, cy, radius,
    resolved.rmax, resolved.thetaZero, resolved.direction);
  assert.equal(label.text, expected.contour_label.text);
  near(label.x, expected.contour_label.x, 1e-4);
  near(label.y, expected.contour_label.y, 1e-4);

  const geometry = colorbarLayout(cx, cy, radius);
  near(geometry.x, expected.colorbar.x);
  near(geometry.y, expected.colorbar.y);
  near(geometry.width, expected.colorbar.width);
  near(geometry.height, expected.colorbar.height);
  assert.deepEqual(colorbarTicks(resolved.colorbar).map((tick) => tick.label),
    expected.colorbar_labels);
});

test("samples large heatmap fields into covering blocks", () => {
  const sampling = heatmapSampling(65, 65);
  assert.equal(sampling.sampled, true);
  assert.equal(sampling.rowStep, 2);
  assert.equal(sampling.colStep, 1);
  assert.equal(sampling.sampledRows, 33);
  assert.equal(sampling.sampledCols, 65);
  assert.equal(sampling.count, 2145);

  const identity = heatmapSampling(64, 64);
  assert.equal(identity.sampled, false);
  assert.equal(identity.rowStep, 1);
  assert.equal(identity.colStep, 1);
  assert.equal(identity.count, HEATMAP_CELL_LIMIT);

  for (const [rows, cols] of [
    [1, 100000], [100000, 1], [3, 5000], [128, 33], [1024, 1024],
  ]) {
    const result = heatmapSampling(rows, cols);
    assert.equal(result.sampled, true);
    assert.ok(result.count <= HEATMAP_CELL_LIMIT,
      `sampled cell count ${result.count} exceeded the cap`);
  }

  const scene = largePolarFieldScene();
  const resolved = resolvePolar(scene);
  const heatmap = resolved.heatmaps[0];
  assert.equal(heatmap.sampled, true);
  assert.equal(heatmap.rowStep, 2);
  assert.equal(heatmap.colStep, 1);
  assert.equal(heatmap.sampledCells, 2145);
  assert.equal(heatmap.values.length, 33);
  assert.equal(heatmap.values[0].length, 65);

  const cells = heatmapCells(heatmap, 272, 117, 73, 2, 0, 1);
  assert.equal(cells.length, 2145);
  assert.equal(cells[0].row, 1);
  assert.equal(cells[0].col, 1);
  assert.equal(cells[0].rowSpan, 2);
  assert.equal(cells[0].colSpan, 1);
  near(cells[0].innerRadius, 0);
  near(cells[0].outerRadius, 2.2461538461538462);
  assert.equal(cells[0].color, "#440154");
  assert.equal(cells[65].row, 3);
  near(cells[65].innerRadius, cells[0].outerRadius);
  const last = cells[cells.length - 1];
  assert.equal(last.row, 65);
  assert.equal(last.col, 65);
  assert.equal(last.rowSpan, 1);
  near(last.innerRadius, 71.87692307692308);
  near(last.outerRadius, 73);
  near(last.endAngle, 2 * Math.PI);
  assert.equal(last.color, "#fde725");

  // A missing range scans the full matrix before sampling, so normalization
  // does not depend on which block values were copied.
  const implicit = largePolarFieldScene();
  implicit.polar.heatmaps[0].vmin = undefined;
  implicit.polar.heatmaps[0].vmax = undefined;
  implicit.polar.heatmaps[0].values[4][4] = Number.NaN;
  const implicitResolved = resolvePolar(implicit);
  const implicitHeatmap = implicitResolved.heatmaps[0];
  assert.equal(implicitHeatmap.sampled, true);
  assert.equal(implicitHeatmap.vmin, 0);
  assert.equal(implicitHeatmap.vmax, 1);
  const implicitCells = heatmapCells(implicitHeatmap, 272, 117, 73, 2, 0, 1);
  assert.equal(implicitCells.length, 2145);
  for (const cell of implicitCells) assert.match(cell.color, /^#[0-9a-f]{6}$/);
});

test("matches the cross-renderer large field fixture", () => {
  const fixture = JSON.parse(readFileSync(
    new URL("./fixtures/polar-parity.json", import.meta.url), "utf8"));
  const expected = fixture.large_field_expected;
  const scene = fixture.large_field_scene;
  scene.polar.heatmaps[0].values = largeFieldValues(expected.rows, expected.cols);
  const resolved = resolvePolar(scene);
  const heatmap = resolved.heatmaps[0];
  assert.equal(heatmap.rowStep, expected.row_step);
  assert.equal(heatmap.colStep, expected.col_step);
  assert.equal(heatmap.sampledCells, expected.sampled_cells);
  assert.equal(heatmap.values.length, expected.sampled_rows);
  assert.equal(heatmap.values[0].length, expected.sampled_cols);

  const layout = fixture.field_layout;
  const { cx, cy, radius } = frameLayout(52, 34, layout.width - 52,
    layout.height - 30, layout.has_colorbar);
  const cells = heatmapCells(heatmap, cx, cy, radius, resolved.rmax,
    resolved.thetaZero, resolved.direction);
  assert.equal(cells.length, expected.sampled_cells);
  const first = cells[0];
  const last = cells[cells.length - 1];
  const firstExpected = expected.first_cell;
  const lastExpected = expected.last_cell;
  assert.equal(first.row, firstExpected.row);
  assert.equal(first.col, firstExpected.col);
  assert.equal(first.rowSpan, firstExpected.row_span);
  assert.equal(first.colSpan, firstExpected.col_span);
  near(first.innerRadius, firstExpected.inner_radius);
  near(first.outerRadius, firstExpected.outer_radius);
  near(first.startAngle, firstExpected.start_angle);
  near(first.endAngle, firstExpected.end_angle);
  assert.equal(first.color, firstExpected.color);
  assert.equal(last.row, lastExpected.row);
  assert.equal(last.col, lastExpected.col);
  assert.equal(last.rowSpan, lastExpected.row_span);
  assert.equal(last.colSpan, lastExpected.col_span);
  near(last.innerRadius, lastExpected.inner_radius);
  near(last.outerRadius, lastExpected.outer_radius);
  near(last.startAngle, lastExpected.start_angle);
  near(last.endAngle, lastExpected.end_angle);
  assert.equal(last.color, lastExpected.color);
});

const PI = Math.PI;

function quiverScene(options = {}) {
  return {
    type: "luaplotlib", orientation: "polar", title: "quiver",
    polar: {
      theta_zero: options.theta_zero ?? 0,
      theta_direction: options.theta_direction ?? "counterclockwise",
      rmax: 6,
      theta_ticks: [{ value: 0, label: "0" }],
      r_ticks: [{ value: 3, label: "3" }],
      series: [{
        kind: "quiver",
        theta: options.theta ?? [0, PI / 2, 0, 0],
        r: options.r ?? [3, 3, 3, 3],
        u: options.u ?? [1, 1, 0, 0],
        v: options.v ?? [0, 0, 1, 1],
        scale: options.scale === undefined ? 20 : options.scale,
        pivot: options.pivot ?? "tail",
        max_arrows: options.max_arrows,
        normalize: options.normalize,
        style: {
          color: "#1f77b4", linewidth: 1.2, head: 5,
          alpha: options.alpha ?? 1,
        },
      }],
    },
  };
}

test("collects quiver IR and projects local components", () => {
  const resolved = resolvePolar(quiverScene());
  const quiver = resolved.series[0];
  assert.equal(quiver.kind, "quiver");
  assert.equal(quiver.count, 4);
  assert.equal(quiver.drawn, 4);
  assert.equal(quiver.stride, 1);
  assert.equal(quiver.maxArrows, QUIVER_DEFAULT_MAX_ARROWS);
  assert.equal(quiver.scale, 20);
  assert.equal(quiver.autoScale, false);
  assert.equal(quiver.pivot, "tail");
  assert.equal(quiver.normalize, false);
  assert.equal(quiver.color, "#1f77b4");
  near(quiver.linewidth, 1.2);
  near(quiver.head, 5);

  const arrows = quiverArrows(quiver, 300, 117, 73, 6, 0, 1);
  assert.equal(arrows.length, 4);
  const first = arrows[0];
  near(first.x, 336.5); near(first.y, 117);
  near(first.tailX, 336.5); near(first.tailY, 117);
  near(first.tipX, 336.5); near(first.tipY, 97);
  near(first.neckX, 336.5); near(first.neckY, 102);
  near(first.angle, -90);
  near(first.length, 20);
  near(first.headX2, 338.75); near(first.headY2, 102);
  near(first.headX3, 334.25); near(first.headY3, 102);
  assert.equal(first.shaft, true);
  assert.equal(first.headed, true);
  near(arrows[1].angle, -180);
  near(arrows[2].angle, 0);
  near(arrows[3].angle, 0);
});

test("quiver follows theta zero and clockwise direction", () => {
  const resolved = resolvePolar(quiverScene({
    theta_zero: PI / 2, theta_direction: "clockwise",
    theta: [0, 0], r: [3, 3], u: [1, 0], v: [0, 1],
  }));
  const arrows = quiverArrows(resolved.series[0], 300, 117, 73, 6,
    resolved.thetaZero, resolved.direction);
  assert.equal(arrows.length, 2);
  near(arrows[0].angle, 0);
  near(arrows[0].tipX, 320);
  near(arrows[0].tipY, 80.5);
  near(arrows[1].angle, -90);
  near(arrows[1].tipX, 300);
  near(arrows[1].tipY, 60.5);
});

test("quiver automatic scale, normalization, and decimation", () => {
  const auto = resolvePolar(quiverScene({
    theta: [0, 0], r: [2, 2], u: [1, 0], v: [0, 2.5], scale: null,
  }));
  const quiver = auto.series[0];
  assert.equal(quiver.autoScale, true);
  near(quiver.scale, QUIVER_AUTO_LENGTH / 2.5);
  const arrows = quiverArrows(quiver, 300, 117, 73, 6, 0, 1);
  near(arrows[0].magnitude, 1);
  near(arrows[0].length, 7.2);
  near(arrows[1].magnitude, 2.5);
  near(arrows[1].length, 18);

  const normalized = resolvePolar(quiverScene({
    theta: [0, 0], r: [2, 2], u: [1, 0], v: [0, 2.5], scale: null,
    normalize: true,
  }));
  near(normalized.series[0].scale, 18);
  const normalizedArrows = quiverArrows(normalized.series[0], 300, 117, 73,
    6, 0, 1);
  near(normalizedArrows[0].length, 18);
  near(normalizedArrows[1].length, 18);

  const theta = [], u = [], v = [];
  for (let index = 0; index < 10; index += 1) {
    theta.push(0); u.push(1); v.push(0);
  }
  u[4] = 0;
  const decimated = resolvePolar(quiverScene({
    theta, r: [3, 3, 3, 3, 3, 3, 3, 3, 3, 3], u, v, max_arrows: 3,
  }));
  const decimatedQuiver = decimated.series[0];
  assert.equal(decimatedQuiver.count, 10);
  assert.equal(decimatedQuiver.maxArrows, 3);
  assert.equal(decimatedQuiver.stride, 4);
  assert.equal(decimatedQuiver.drawn, 2);
  const decimatedArrows = quiverArrows(decimatedQuiver, 300, 117, 73, 6, 0, 1);
  assert.deepEqual(decimatedArrows.map((arrow) => arrow.index), [1, 9]);
});

test("clamps quiver options and tolerates malformed data", () => {
  const scene = {
    type: "luaplotlib", orientation: "polar",
    polar: {
      rmax: 6,
      series: [
        {
          kind: "quiver", theta: [0 / 0, 0], r: [3, 4],
          u: [1, 1], v: [0, 0], max_arrows: 100000,
          style: { linewidth: -1, head: -2, color: "#ff7f0e" },
        },
        { kind: "quiver", theta: [0], r: [2] },
      ],
    },
  };
  const resolved = resolvePolar(scene);
  assert.equal(resolved.series.length, 2);
  const first = resolved.series[0];
  assert.equal(first.maxArrows, QUIVER_MAX_ARROWS);
  assert.equal(first.stride, 1);
  assert.equal(first.drawn, 1);
  assert.equal(first.linewidth, 0);
  assert.equal(first.head, 0);
  assert.equal(resolved.series[1].drawn, 0);
  assert.equal(resolved.series[1].count, 1);
});

test("matches the cross-renderer quiver fixture", () => {
  const fixture = JSON.parse(readFileSync(
    new URL("./fixtures/polar-parity.json", import.meta.url), "utf8"));
  const scene = fixture.quiver_scene;
  const expected = fixture.quiver_expected;
  const resolved = resolvePolar(scene);
  const quiver = resolved.series[0];
  assert.equal(quiver.kind, "quiver");
  assert.equal(quiver.count, expected.count);
  assert.equal(quiver.drawn, expected.drawn);
  assert.equal(quiver.stride, expected.stride);
  assert.equal(quiver.maxArrows, expected.max_arrows);
  near(quiver.scale, expected.scale);
  assert.equal(quiver.autoScale, expected.scale_mode === "auto");
  assert.equal(quiver.pivot, expected.pivot);

  const layout = fixture.layout;
  const { cx, cy, radius } = frameLayout(52, 34, layout.width - 52,
    layout.height - 30, false);
  assert.equal(cx, layout.cx);
  assert.equal(cy, layout.cy);
  assert.equal(radius, layout.radius);
  const arrows = quiverArrows(quiver, cx, cy, radius, resolved.rmax,
    resolved.thetaZero, resolved.direction);
  assert.equal(arrows.length, expected.arrows.length);
  arrows.forEach((arrow, index) => {
    const want = expected.arrows[index];
    assert.equal(arrow.index, want.index);
    near(arrow.angle, want.angle, 1e-9, "quiver angle");
    near(arrow.magnitude, want.magnitude, 1e-9, "quiver magnitude");
    near(arrow.tailX, want.tail_x, 1e-9, "quiver tail x");
    near(arrow.tailY, want.tail_y, 1e-9, "quiver tail y");
    near(arrow.tipX, want.tip_x, 1e-9, "quiver tip x");
    near(arrow.tipY, want.tip_y, 1e-9, "quiver tip y");
    near(arrow.neckX, want.neck_x, 1e-9, "quiver neck x");
    near(arrow.neckY, want.neck_y, 1e-9, "quiver neck y");
  });
});
