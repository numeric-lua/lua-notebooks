// Deterministic scenes shared by the Node unit tests and the headless
// Chromium scene QA page.  Keeping one fixture module means the browser QA
// exercises the same IR the unit tests inspect.

const PI = Math.PI;

export function polarScene() {
  const theta = [], r = [];
  for (let index = 1; index <= 96; index += 1) {
    const angle = ((index - 1) * 2 * PI) / 96;
    theta.push(angle);
    r.push(1 + 0.8 * Math.sin(4 * angle));
  }
  return {
    type: "luaplotlib",
    orientation: "polar",
    title: "polar rose",
    width: 800,
    height: 320,
    polar: {
      theta_zero: 0,
      theta_direction: "counterclockwise",
      rmax: 2,
      theta_ticks: [
        { value: 0, label: "0" },
        { value: PI / 2, label: "90" },
        { value: PI, label: "180" },
        { value: (3 * PI) / 2, label: "270" },
      ],
      r_ticks: [
        { value: 0.5, label: "0.5" },
        { value: 1, label: "1" },
        { value: 1.5, label: "1.5" },
        { value: 2, label: "2" },
      ],
      series: [
        {
          kind: "line", theta, r,
          style: { color: "#1f77b4", label: "rose" },
        },
        {
          kind: "scatter", theta: [0, PI / 2, PI], r: [1, 2, 1],
          style: { color: "#ff7f0e", radius: 5, label: "samples" },
        },
        {
          kind: "bar", theta: [PI / 4], r: [1.5],
          widths: [0.45], colors: ["#2ca02c"],
        },
      ],
    },
  };
}

export function polarFallbackScene() {
  return {
    type: "luaplotlib",
    orientation: "polar",
    polar: {
      theta_direction: "clockwise",
      series: [
        { kind: "line", theta: [0, PI / 2], r: [1, -2.5] },
      ],
    },
  };
}

export function emptyPolarScene() {
  return { type: "luaplotlib", orientation: "polar", polar: {} };
}


export function polarFieldScene() {
  const PI = Math.PI;
  return {
    type: "luaplotlib",
    orientation: "polar",
    title: "polar field",
    polar: {
      theta_zero: 0,
      theta_direction: "counterclockwise",
      rmax: 2,
      theta_ticks: [
        { value: 0, label: "0" },
        { value: PI / 2, label: "90" },
      ],
      r_ticks: [
        { value: 0.5, label: "0.5" },
        { value: 1, label: "1" },
        { value: 1.5, label: "1.5" },
        { value: 2, label: "2" },
      ],
      heatmaps: [{
        rows: 2, cols: 3,
        values: [[0, 1, 2], [3, 4, 5]],
        vmin: 0, vmax: 5, rmin: 0.5, rmax: 2,
        theta_min: 0, theta_max: PI, alpha: 0.9,
        label: "field", colorbar: true,
      }],
      contours: [{
        rows: 3, cols: 3,
        levels: [{
          level: 2.5,
          segments: [
            [0, 0.5, PI / 2, 1.5],
            [PI, 1.0, (3 * PI) / 2, 2.0],
          ],
        }],
        labels: true,
        style: {
          color: "#e45756", linewidth: 1.25, alpha: 0.8,
          linestyle: "dashed", label: "isoline",
        },
      }],
      colorbar: {
        orientation: "vertical", vmin: 0, vmax: 5,
        ticks: [0, 2.5, 5], label: "density",
      },
      series: [{
        kind: "line", theta: [0, PI / 2], r: [1, 2],
        style: { color: "#1f77b4", label: "overlay" },
      }],
    },
  };
}

export function polarQuiverScene() {
  return {
    type: "luaplotlib",
    orientation: "polar",
    title: "polar quiver",
    polar: {
      theta_zero: 0,
      theta_direction: "counterclockwise",
      rmax: 6,
      theta_ticks: [
        { value: 0, label: "0" },
        { value: PI / 2, label: "90" },
        { value: PI, label: "180" },
        { value: (3 * PI) / 2, label: "270" },
      ],
      r_ticks: [
        { value: 2, label: "2" },
        { value: 4, label: "4" },
        { value: 6, label: "6" },
      ],
      series: [{
        kind: "quiver",
        theta: [0, PI / 2, PI, (3 * PI) / 2],
        r: [3, 3, 3, 3],
        u: [1, 1, 1, 1],
        v: [0.5, 0.5, 0.5, 0.5],
        scale: 16,
        pivot: "middle",
        max_arrows: 64,
        normalize: false,
        style: {
          color: "#ff7f0e", linewidth: 1.5, head: 6, alpha: 1,
          label: "flow",
        },
      }],
    },
  };
}

export function polarStreamplotScene() {
  const lines = [];
  for (let line = 0; line < 2; line += 1) {
    const theta = [];
    const r = [];
    for (let index = 0; index < 13; index += 1) {
      theta.push(line * PI + index * 0.5);
      r.push(0.5 + index * 0.1 + line * 0.35);
    }
    lines.push({
      theta,
      r,
      points: theta.length,
      arrows: [{
        theta: theta[6],
        r: r[6],
        angle: line === 0 ? -70 : 110,
      }],
    });
  }
  return {
    type: "luaplotlib",
    orientation: "polar",
    title: "polar streamplot",
    polar: {
      theta_zero: 0,
      theta_direction: "counterclockwise",
      rmax: 2.4,
      theta_ticks: [
        { value: 0, label: "0" },
        { value: PI / 2, label: "90" },
        { value: PI, label: "180" },
        { value: (3 * PI) / 2, label: "270" },
      ],
      r_ticks: [
        { value: 1, label: "1" },
        { value: 2, label: "2" },
      ],
      series: [{
        kind: "streamplot",
        theta: [0, PI / 2, PI, (3 * PI) / 2, 2 * PI],
        r: [0.25, 0.75, 1.25, 1.75, 2.25],
        lines,
        periodic: true,
        density: 1,
        step: 0.08,
        step_mode: "explicit",
        resolved_step: 0.08,
        step_unit: "data_radius_units",
        max_steps: 300,
        max_lines: 16,
        max_points: 800,
        arrows: true,
        head: 6,
        truncated: false,
        style: {
          color: "#2ca02c", linewidth: 2, head: 8, alpha: 1,
          label: "flow",
        },
      }],
    },
  };
}

// Generate the deterministic matrix used by the large-field parity fixture:
// rows run from the inner radius to the outer radius, values are (row-1)/(rows-1).
export function largeFieldValues(rows = 65, cols = 65) {
  const values = [];
  for (let row = 1; row <= rows; row += 1) {
    const line = [];
    for (let col = 1; col <= cols; col += 1) {
      line.push((row - 1) / (rows - 1));
    }
    values.push(line);
  }
  return values;
}

export function largePolarFieldScene(rows = 65, cols = 65) {
  return {
    type: "luaplotlib",
    orientation: "polar",
    title: "large polar field",
    polar: {
      rmax: 2,
      theta_ticks: [{ value: 0, label: "0" }],
      r_ticks: [
        { value: 1, label: "1" },
        { value: 2, label: "2" },
      ],
      heatmaps: [{
        rows, cols,
        values: largeFieldValues(rows, cols),
        vmin: 0, vmax: 1, rmin: 0, rmax: 2,
        theta_min: 0, theta_max: 2 * PI,
        alpha: 1, label: "large", colorbar: true,
      }],
      colorbar: {
        vmin: 0, vmax: 1, ticks: [0, 0.5, 1], label: "density",
      },
      series: [{
        kind: "line", theta: [0, PI / 2], r: [1, 2],
        style: { color: "#1f77b4", label: "overlay" },
      }],
    },
  };
}

export function cartesianScene() {
  const xs = [], ys = [];
  for (let index = 1; index <= 80; index += 1) {
    const x = (index - 1) * 0.1;
    xs.push(x);
    ys.push(Math.sin(x));
  }
  return {
    type: "luaplotlib",
    title: "sin(x)",
    xlabel: "x",
    ylabel: "y",
    xlim: [0, 8],
    ylim: [-1.2, 1.2],
    grid: true,
    series: [
      {
        kind: "line", x: xs, y: ys,
        style: { color: "#8aa4ff", width: 2, label: "sin" },
      },
      {
        kind: "scatter", x: [0, PI / 2, PI], y: [0, 1, 0],
        style: { color: "#ff9f6e", radius: 4, label: "samples" },
      },
    ],
  };
}

export function histogramScene() {
  return {
    type: "luaplotlib",
    title: "histogram",
    xlabel: "value",
    series: [
      {
        kind: "hist",
        edges: [0, 1, 2, 3, 4, 5],
        counts: [2, 6, 4, 8, 3],
        style: { color: "#54a24b", label: "counts" },
      },
    ],
  };
}

export function categoryScene() {
  return {
    type: "luaplotlib",
    title: "categories",
    category_ticks: [
      { position: 1, label: "alpha" },
      { position: 2, label: "beta" },
      { position: 3, label: "gamma" },
    ],
    series: [
      {
        kind: "bar", x: [1, 2, 3], y: [2, 5, 3], width: 0.6,
        style: { color: "#b279a2" },
      },
    ],
  };
}

export function longSeriesScene() {
  const x = [], y = [];
  for (let index = 0; index < 1600; index += 1) {
    x.push(index);
    y.push(Math.sin(index / 20));
  }
  return {
    type: "luaplotlib",
    title: "long series",
    xlim: [0, 1599],
    series: [{ kind: "line", x, y, style: { color: "#6ecbff" } }],
  };
}

export const sceneMatrix = [
  { name: "polar", scene: polarScene, seriesColor: [31, 119, 180], minSeriesPixels: 30 },
  { name: "polar-fallback", scene: polarFallbackScene, seriesColor: [76, 120, 168], minSeriesPixels: 10 },
  { name: "polar-empty", scene: emptyPolarScene, seriesColor: [66, 80, 106], minSeriesPixels: 50 },
  { name: "polar-field", scene: polarFieldScene, seriesColor: [31, 119, 180], minSeriesPixels: 20 },
  { name: "large-polar-field", scene: () => largePolarFieldScene(96, 96), seriesColor: [31, 119, 180], minSeriesPixels: 20 },
  { name: "polar-quiver", scene: polarQuiverScene, seriesColor: [255, 127, 14], minSeriesPixels: 10 },
  { name: "polar-streamplot", scene: polarStreamplotScene, seriesColor: [44, 160, 44], minSeriesPixels: 10 },
  { name: "cartesian", scene: cartesianScene, seriesColor: [138, 164, 255], minSeriesPixels: 30 },
  { name: "histogram", scene: histogramScene, seriesColor: [84, 162, 75], minSeriesPixels: 30 },
  { name: "categories", scene: categoryScene, seriesColor: [178, 121, 162], minSeriesPixels: 30 },
  { name: "long-series", scene: longSeriesScene, seriesColor: [110, 203, 255], minSeriesPixels: 30 },
  { name: "cube", scene: () => "cube", seriesColor: null, minSeriesPixels: 0 },
  { name: "grid", scene: () => "grid", seriesColor: null, minSeriesPixels: 0 },
];
