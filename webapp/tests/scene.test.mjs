import test from "node:test";
import assert from "node:assert/strict";
import { paintScene } from "../js/scene.js";
import { HEATMAP_CELL_LIMIT } from "../js/polar.js";
import {
  cartesianScene, categoryScene, emptyPolarScene, histogramScene,
  largePolarFieldScene, longSeriesScene, polarFieldScene, polarScene,
} from "./fixtures.js";

function fakeCanvas(width = 600, height = 230) {
  const calls = [];
  const record = (name) => (...args) => { calls.push({ name, args }); };
  const ctx = {
    save: record("save"), restore: record("restore"),
    setTransform: record("setTransform"), clearRect: record("clearRect"),
    beginPath: record("beginPath"), closePath: record("closePath"),
    moveTo: record("moveTo"), lineTo: record("lineTo"), arc: record("arc"),
    clip: record("clip"),
    fill: record("fill"), stroke: record("stroke"), fillRect: record("fillRect"),
    fillText: record("fillText"), translate: record("translate"),
    rotate: record("rotate"), setLineDash: record("setLineDash"),
  };
  const canvas = {
    width: 0,
    height: 0,
    getContext: () => ctx,
    getBoundingClientRect: () => ({ width, height }),
  };
  return { canvas, calls, ctx };
}

function named(calls, name) {
  return calls.filter((call) => call.name === name);
}

function textValues(calls) {
  return named(calls, "fillText").map((call) => String(call.args[0]));
}

function near(actual, expected, tolerance = 1e-9, label = "value") {
  assert.ok(Math.abs(actual - expected) <= tolerance,
    `${label}: expected ${expected}, got ${actual}`);
}

function assertFiniteCalls(calls) {
  for (const call of calls) {
    for (const arg of call.args) {
      if (typeof arg === "number") {
        assert.ok(Number.isFinite(arg), `${call.name} received ${arg}`);
      }
    }
  }
}

test("draws the polar frame, rings, spokes, labels, and series", () => {
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, polarScene());
  const arcs = named(calls, "arc");
  // Four rings, the frame, three scatter points, and one bar sector.
  assert.equal(arcs.length, 9);
  const frame = arcs.find((call) => Math.abs(call.args[2] - 73) < 1e-9);
  assert.ok(frame, "missing 73px frame/ring");
  const ring = arcs.find((call) => Math.abs(call.args[2] - 18.25) < 1e-9);
  assert.ok(ring, "missing first radius ring");

  const path = named(calls, "moveTo").find((call) =>
    Math.abs(call.args[0] - 336.5) < 1e-9 && Math.abs(call.args[1] - 117) < 1e-9);
  assert.ok(path, "line series did not start at the projected point");

  const bar = arcs.find((call) => Math.abs(call.args[2] - 54.75) < 1e-9
    && call.args[5] === true);
  assert.ok(bar, "missing counterclockwise bar wedge");

  const texts = textValues(calls);
  for (const expected of ["polar rose", "0", "90", "180", "270", "0.5", "1", "1.5", "2"]) {
    assert.ok(texts.includes(expected), `missing label ${expected}`);
  }
  assert.equal(named(calls, "fillRect").length, 1);
  assertFiniteCalls(calls);
});

test("draws fallback rings and spokes for an empty polar scene", () => {
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, emptyPolarScene());
  assert.equal(named(calls, "arc").length, 5); // four rings and the frame
  assert.equal(named(calls, "stroke").length, 17); // four rings, twelve spokes, frame
  const texts = textValues(calls);
  assert.equal(texts.length, 16); // four radius labels and twelve degree labels
  assert.ok(texts.includes("0.25"));
  assert.ok(texts.includes("360°") || texts.includes("0°"));
});

test("long polar labels are omitted by the browser too", () => {
  const longRadius = "r".repeat(40);
  const longTheta = "t".repeat(40);
  const scene = {
    type: "luaplotlib", orientation: "polar",
    polar: {
      rmax: 1,
      r_ticks: [{ value: 0.5, label: longRadius }],
      theta_ticks: [{ value: 0, label: longTheta }],
    },
  };
  const { canvas, calls } = fakeCanvas();
  paintScene(canvas, scene);
  const texts = textValues(calls);
  assert.ok(!texts.includes(longRadius));
  assert.ok(!texts.includes(longTheta));
});

test("does not overflow the frame for out-of-range polar data", () => {
  const scene = {
    type: "luaplotlib", orientation: "polar",
    polar: {
      rmax: 2,
      theta_ticks: [{ value: 1, label: "1" }],
      series: [
        { kind: "line", theta: [0, 1 / 0, 2], r: [1, 2, 0 / 0] },
        { kind: "line", theta: [0, 0], r: [0, 99] },
      ],
    },
  };
  const { canvas, calls } = fakeCanvas();
  paintScene(canvas, scene);
  const frame = named(calls, "arc").find((call) => Math.abs(call.args[2] - 73) < 1e-9);
  assert.ok(frame);
  const endpoint = named(calls, "lineTo").find((call) =>
    Math.abs(call.args[0] - 373) < 1e-9 && Math.abs(call.args[1] - 117) < 1e-9);
  assert.ok(endpoint, "oversized radius did not clamp to the frame");
  assertFiniteCalls(calls);
});

test("renders histogram bars from edges and counts", () => {
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, histogramScene());
  const rects = named(calls, "fillRect");
  assert.equal(rects.length, 1 + 5); // scene background and five bins
  for (const rect of rects) {
    assert.ok(rect.args[2] >= 1, "bar width collapsed");
    assert.ok(rect.args[3] >= 0, "negative bar height");
  }
  assert.ok(textValues(calls).includes("histogram"));
  assertFiniteCalls(calls);
});

test("renders categorical ticks instead of numeric x labels", () => {
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, categoryScene());
  const texts = textValues(calls);
  for (const label of ["alpha", "beta", "gamma"]) {
    assert.ok(texts.includes(label), `missing category ${label}`);
  }
  assert.equal(named(calls, "fillRect").length, 1 + 3);
});

test("honours explicit Cartesian bar widths", () => {
  const wide = categoryScene();
  const narrow = JSON.parse(JSON.stringify(categoryScene()));
  narrow.series[0].width = 0.1;
  const first = fakeCanvas();
  paintScene(first.canvas, wide);
  const second = fakeCanvas();
  paintScene(second.canvas, narrow);
  const wideWidth = named(first.calls, "fillRect")[1].args[2];
  const narrowWidth = named(second.calls, "fillRect")[1].args[2];
  assert.ok(wideWidth > narrowWidth * 3,
    `expected width 0.6 to beat 0.1 (${wideWidth} vs ${narrowWidth})`);
});

test("caps long Cartesian line sampling", () => {
  const scene = longSeriesScene();
  scene.grid = false;
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, scene);
  const lineTo = named(calls, "lineTo").length;
  assert.ok(lineTo <= 801, `expected at most 801 segments, got ${lineTo}`);
  assert.ok(lineTo >= 700, `expected sampled line, got ${lineTo}`);
  assertFiniteCalls(calls);
});

test("paints cube, grid, and unknown scene placeholders", () => {
  for (const scene of ["cube", "grid"]) {
    const { canvas, calls } = fakeCanvas();
    paintScene(canvas, scene);
    assert.ok(named(calls, "stroke").length >= 12, `${scene} did not draw edges`);
    assert.ok(textValues(calls).some((text) => text.startsWith(`${scene} ·`)));
  }
  const { canvas, calls } = fakeCanvas();
  paintScene(canvas, { type: "extension" });
  const texts = textValues(calls);
  assert.ok(texts.includes("scene output"));
  assert.ok(texts.includes("renderer not available for this scene type"));
});

test("does not call the renderer with non-finite Cartesian data", () => {
  const scene = cartesianScene();
  scene.series[0].x.push(1 / 0);
  scene.series[0].y.push(0 / 0);
  scene.series.push({ kind: "bar", x: [1 / 0, 2], y: [1, 0 / 0] });
  const { canvas, calls } = fakeCanvas();
  paintScene(canvas, scene);
  assertFiniteCalls(calls);
});

test("renders polar heatmap cells, contours, and a colorbar", () => {
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, polarFieldScene());
  assert.equal(named(calls, "fillRect").length, 1 + 40); // background + colorbar
  const colorbar = named(calls, "fillRect")[1];
  near(colorbar.args[0], 361);
  near(colorbar.args[1], 54.95);
  near(colorbar.args[2], 16);

  const arcs = named(calls, "arc");
  // Four rings, the frame, and two arcs per annular heatmap cell (six cells).
  assert.equal(arcs.length, 5 + 12);
  assert.ok(arcs.some((call) => Math.abs(call.args[2] - 73) < 1e-9));

  const texts = textValues(calls);
  for (const expected of ["polar field", "density", "2.5", "0.5", "90"]) {
    assert.ok(texts.includes(expected), `missing label ${expected}`);
  }
  assert.ok(named(calls, "setLineDash").some((call) => call.args[0].length === 2));
  assert.ok(named(calls, "stroke").length >= 2, "contours were not stroked");
  assertFiniteCalls(calls);
});

test("caps large polar heatmap draw calls", () => {
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, largePolarFieldScene(96, 96));
  const fills = named(calls, "fill").length;
  assert.ok(fills <= HEATMAP_CELL_LIMIT,
    `large field painted ${fills} cells, above the ${HEATMAP_CELL_LIMIT} cap`);
  assert.ok(fills > 1000, "large field did not paint a sampled field");
  assertFiniteCalls(calls);
});

test("splits a full-turn annular heatmap into convex parts", () => {
  const scene = {
    type: "luaplotlib", orientation: "polar",
    polar: {
      rmax: 1,
      heatmaps: [{
        rows: 1, cols: 1, values: [[1]], vmin: 0, vmax: 1,
        rmin: 0.5, rmax: 1, theta_min: 0, theta_max: 2 * Math.PI,
      }],
    },
  };
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, scene);
  const fills = named(calls, "fill");
  assert.ok(fills.length >= 48, `expected 48 wedges, got ${fills.length}`);
  assertFiniteCalls(calls);
});

test("draws polar quiver shafts and heads inside the circle", () => {
  const scene = {
    type: "luaplotlib", orientation: "polar", grid: false,
    polar: {
      rmax: 6,
      series: [{
        kind: "quiver",
        theta: [0, Math.PI / 2], r: [3, 3],
        u: [1, 1], v: [0, 0], scale: 20, pivot: "tail",
        style: { color: "#1f77b4", linewidth: 1.2, head: 5 },
      }],
    },
  };
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, scene);
  assert.equal(named(calls, "clip").length, 1);
  assert.equal(named(calls, "stroke").length, 3); // frame plus two shafts
  assert.equal(named(calls, "fill").length, 2); // two arrow heads
  const moves = named(calls, "moveTo");
  assert.ok(moves.some((call) => Math.abs(call.args[0] - 336.5) < 1e-9
    && Math.abs(call.args[1] - 117) < 1e-9), "missing first shaft tail");
  assert.ok(moves.some((call) => Math.abs(call.args[0] - 300) < 1e-9
    && Math.abs(call.args[1] - 80.5) < 1e-9), "missing second shaft tail");
  assertFiniteCalls(calls);
});

test("draws polar streamlines and mid-line arrows inside the circle", () => {
  const scene = {
    type: "luaplotlib", orientation: "polar", grid: false,
    polar: {
      rmax: 2,
      series: [{
        kind: "streamplot",
        theta: [0, Math.PI / 2, Math.PI, (3 * Math.PI) / 2, 2 * Math.PI],
        r: [0.5, 1, 1.5, 2],
        head: 6,
        style: { color: "#2ca02c", linewidth: 1.5, alpha: 0.9 },
        lines: [
          {
            theta: [0, 0.5, 1], r: [1, 1.2, 1.4],
            arrows: [{ theta: 0.5, r: 1.2, angle: -30 }],
          },
          {
            theta: [2, 2.5, 3, 3.5], r: [0.8, 0.9, 1, 1.1],
            arrows: [{ theta: 3, r: 1, angle: 120 }],
          },
        ],
      }],
    },
  };
  const { canvas, calls } = fakeCanvas(600, 230);
  paintScene(canvas, scene);
  assert.equal(named(calls, "clip").length, 1);
  assert.equal(named(calls, "stroke").length, 3); // frame plus two lines
  assert.equal(named(calls, "fill").length, 2); // two arrow heads
  const moves = named(calls, "moveTo");
  assert.ok(moves.some((call) => Math.abs(call.args[0] - 336.5) < 1e-9
    && Math.abs(call.args[1] - 117) < 1e-9), "missing first line start");
  assert.ok(named(calls, "lineTo").length >= 5, "streamlines were not drawn");
  assertFiniteCalls(calls);
});
