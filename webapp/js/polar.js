// Shared polar geometry for the browser scene renderer.
//
// This is the dependency-free JavaScript counterpart of notebook/polar.lua:
// the desktop viewport, the static HTML export, and this webapp all consume
// the same luaplotlib IR.  Keep rmax fallback, projection, tick filtering,
// labels, sampling caps, and bar wedges in sync with the Lua module.

export const PALETTE = ["#4c78a8", "#f58518", "#54a24b", "#b279a2", "#e45756", "#72b7b2"];

export const LINE_SAMPLE_LIMIT = 800;
export const SCATTER_SAMPLE_LIMIT = 400;
export const BAR_SAMPLE_LIMIT = 400;
export const RADIUS_LABEL_LIMIT = 12;
export const THETA_LABEL_LIMIT = 18;
export const THETA_LABEL_GAP = 12;
export const DEFAULT_BAR_WIDTH = 0.2;
export const DEFAULT_POINT_RADIUS = 2.6;
export const MAX_POINT_RADIUS = 8;
export const MIN_POINT_RADIUS = 1;

const TAU = Math.PI * 2;

export function finiteNumber(value) {
  return typeof value === "number" && Number.isFinite(value);
}

export function validColor(value) {
  return typeof value === "string" && /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i.test(value) ? value : null;
}

function polarObject(scene) {
  return scene && typeof scene === "object" && scene.polar && typeof scene.polar === "object"
    ? scene.polar : {};
}

function array(value) {
  return Array.isArray(value) ? value : [];
}

// Pull the polar options out of a scene.  An explicit rmax must be positive;
// otherwise the caller falls back to the largest observed radius.
export function polarConfig(scene) {
  const polar = polarObject(scene);
  const rmax = finiteNumber(polar.rmax) && polar.rmax > 0 ? polar.rmax : null;
  const thetaZero = finiteNumber(polar.theta_zero) ? polar.theta_zero : 0;
  const direction = polar.theta_direction === "clockwise" ? -1 : 1;
  return { polar, rmax, thetaZero, direction };
}

// Map the IR into the compact point/bar shapes all three renderers use.
// Values are copied so drawing never mutates kernel data.
export function collectPolar(scene) {
  const polar = polarObject(scene);
  const collected = [];
  let observed = 0;
  let paletteIndex = 0;

  for (const item of array(polar.series)) {
    if (!item || typeof item !== "object") continue;
    const style = item.style && typeof item.style === "object" ? item.style : {};
    let color = validColor(style.color);
    if (color === null) {
      paletteIndex += 1;
      color = PALETTE[(paletteIndex - 1) % PALETTE.length];
    }
    const alpha = finiteNumber(style.alpha) ? style.alpha : 1;
    const theta = item.theta;
    const r = item.r;
    if (!Array.isArray(theta) || !Array.isArray(r)) continue;
    const count = Math.min(theta.length, r.length);
    if (item.kind === "bar") {
      const widths = array(item.widths);
      const colors = array(item.colors);
      const bars = [];
      for (let index = 0; index < count; index += 1) {
        if (!finiteNumber(theta[index]) || !finiteNumber(r[index])) continue;
        observed = Math.max(observed, Math.abs(r[index]));
        const width = finiteNumber(widths[index])
          ? Math.max(0.001, widths[index]) : DEFAULT_BAR_WIDTH;
        const barColor = validColor(colors[index]);
        bars.push({ theta: theta[index], r: r[index], width, color: barColor || color });
      }
      if (bars.length) collected.push({ kind: "bar", bars, color, alpha });
    } else {
      const radii = array(item.radii);
      const colors = array(item.colors);
      const styleRadius = finiteNumber(style.radius) ? style.radius : null;
      const points = [];
      for (let index = 0; index < count; index += 1) {
        if (!finiteNumber(theta[index]) || !finiteNumber(r[index])) continue;
        observed = Math.max(observed, Math.abs(r[index]));
        points.push({
          theta: theta[index],
          r: r[index],
          radius: finiteNumber(radii[index]) ? radii[index] : styleRadius,
          color: validColor(colors[index]),
        });
      }
      if (points.length) {
        collected.push({
          kind: item.kind === "scatter" ? "scatter" : "line",
          points, color, alpha,
        });
      }
    }
  }
  return { series: collected, observed };
}

// Resolve the axis options, effective rmax, and filtered series in one place.
export function resolvePolar(scene) {
  const { polar, rmax, thetaZero, direction } = polarConfig(scene);
  const { series, observed } = collectPolar(scene);
  return {
    polar,
    series,
    observed,
    rmax: rmax ?? (observed > 0 ? observed : 1),
    thetaZero,
    direction,
  };
}

// Ring ticks are filtered to positive values inside rmax.  Scenes without
// r_ticks get four evenly spaced rings.
export function polarRings(polar, rmax) {
  const rings = [];
  for (const tick of array(polar && polar.r_ticks)) {
    if (tick && typeof tick === "object" && finiteNumber(tick.value)
      && tick.value > 0 && tick.value <= rmax * (1 + 1e-9)) {
      rings.push(tick);
    }
  }
  if (!rings.length) {
    for (let index = 1; index <= 4; index += 1) rings.push({ value: (rmax * index) / 4 });
  }
  return rings;
}

// Spoke ticks accept any finite theta.  Scenes without theta_ticks get the
// usual twelve-spoke fallback.
export function polarSpokes(polar) {
  const spokes = [];
  for (const tick of array(polar && polar.theta_ticks)) {
    if (tick && typeof tick === "object" && finiteNumber(tick.value)) spokes.push(tick);
  }
  if (!spokes.length) {
    for (let index = 0; index < 12; index += 1) spokes.push({ value: (index * Math.PI) / 6 });
  }
  return spokes;
}

function fallbackNumber(value, suffix = "") {
  if (!finiteNumber(value)) return null;
  let text;
  if (value === 0) {
    text = "0";
  } else {
    text = Number(value.toPrecision(4)).toString();
  }
  return text + suffix;
}

// Explicit labels are used when short enough; long labels are omitted rather
// than clipped.  Missing labels fall back to a compact numeric value.
export function radiusLabel(tick) {
  if (!tick || typeof tick !== "object") return null;
  if (typeof tick.label === "string") {
    if (tick.label === "") return fallbackNumber(tick.value);
    if (tick.label.length <= RADIUS_LABEL_LIMIT) return tick.label;
    return null;
  }
  return fallbackNumber(tick.value);
}

export function thetaLabel(tick) {
  if (!tick || typeof tick !== "object") return null;
  if (typeof tick.label === "string") {
    if (tick.label === "") return fallbackNumber(tick.value * 180 / Math.PI, "°");
    if (tick.label.length <= THETA_LABEL_LIMIT) return tick.label;
    return null;
  }
  return fallbackNumber(tick.value * 180 / Math.PI, "°");
}

// Samples are capped so a huge kernel series never stalls a frame.  The stride
// matches the Lua renderer.
export function sampleStep(count, limit = LINE_SAMPLE_LIMIT) {
  if (!finiteNumber(count) || count <= 0) return 1;
  return Math.max(1, Math.ceil(count / limit));
}

// Largest circle that fits the plot box, with the historical 10px breathing
// room used by the live and SVG renderers.
export function frameRadius(plotW, plotH) {
  return Math.max(1, Math.min(plotW, plotH) / 2 - 10);
}

// Project polar data into y-down screen coordinates.  Radii outside rmax clamp
// to the frame instead of overflowing the viewport.
export function projectPolar(cx, cy, radius, rmax, thetaZero, direction, theta, value) {
  const angle = thetaZero + direction * theta;
  let ratio = value / rmax;
  if (ratio > 1) ratio = 1; else if (ratio < -1) ratio = -1;
  return {
    x: cx + radius * ratio * Math.cos(angle),
    y: cy - radius * ratio * Math.sin(angle),
    angle,
  };
}

export function ringLabelPosition(cx, cy, ringRadius) {
  return { x: cx + ringRadius - 3, y: cy + 3 };
}

export function thetaLabelPosition(cx, cy, radius, angle) {
  const labelRadius = radius + THETA_LABEL_GAP;
  return {
    x: cx + labelRadius * Math.cos(angle),
    y: cy - labelRadius * Math.sin(angle) + 3,
  };
}

// Clamp a per-point scatter radius exactly like the SVG preview.
export function pointRadius(point) {
  let value = point && typeof point === "object" ? point.radius : undefined;
  if (!finiteNumber(value)) value = DEFAULT_POINT_RADIUS;
  return Math.max(MIN_POINT_RADIUS, Math.min(MAX_POINT_RADIUS, value));
}

// Split a polar bar into convex filled sectors.  A bar wider than a half turn
// becomes multiple sectors; a full turn becomes a filled circle.  Returned
// angles are in screen/world angle space (theta_zero and theta_direction
// included), so the canvas arc and the SVG arc share one geometry.
export function barSectors(bar, radius, rmax, thetaZero, direction) {
  if (!bar || typeof bar !== "object") return [];
  if (!finiteNumber(bar.r) || !finiteNumber(bar.theta)) return [];
  let ratio = Math.abs(bar.r) / rmax;
  if (ratio > 1) ratio = 1;
  if (ratio <= 0) return [];
  const width = finiteNumber(bar.width) ? bar.width : DEFAULT_BAR_WIDTH;
  const half = Math.min(Math.PI, Math.abs(width) / 2);
  const span = half * 2;
  if (span <= 1e-12) return [];
  const theta = bar.theta + (bar.r < 0 ? Math.PI : 0);
  const barRadius = radius * ratio;
  if (span >= TAU - 1e-9) {
    return [{ full: true, radius: barRadius, ratio, color: bar.color }];
  }
  const count = Math.max(1, Math.ceil(span / Math.PI));
  const step = span / count;
  const sectors = [];
  for (let index = 1; index <= count; index += 1) {
    const startAngle = theta - half + (index - 1) * step;
    const endAngle = startAngle + step;
    sectors.push({
      radius: barRadius,
      ratio,
      color: bar.color,
      startAngle: thetaZero + direction * startAngle,
      endAngle: thetaZero + direction * endAngle,
    });
  }
  return sectors;
}
