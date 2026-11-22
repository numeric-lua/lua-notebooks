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
export const QUIVER_AUTO_LENGTH = 18;
export const QUIVER_DEFAULT_MAX_ARROWS = 512;
export const QUIVER_MAX_ARROWS = 4096;
export const QUIVER_DEFAULT_HEAD = 5;
export const QUIVER_DEFAULT_LINEWIDTH = 1.2;
export const STREAM_DEFAULT_HEAD = 6;
export const STREAM_DEFAULT_LINEWIDTH = 1.5;
export const STREAM_DEFAULT_DENSITY = 1;
export const STREAM_DEFAULT_MAX_STEPS = 300;
export const STREAM_DEFAULT_MAX_LINES = 64;
export const STREAM_DEFAULT_MAX_POINTS = 8000;

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
    } else if (item.kind === "quiver") {
      const u = Array.isArray(item.u) ? item.u : null;
      const v = Array.isArray(item.v) ? item.v : null;
      const normalize = item.normalize === true;
      const requested = Number.isInteger(item.max_arrows) && item.max_arrows >= 1
        ? item.max_arrows : QUIVER_DEFAULT_MAX_ARROWS;
      const maxArrows = Math.max(1, Math.min(QUIVER_MAX_ARROWS, requested));
      // luaplotlib decimates with ceil(count / max_arrows) over the source
      // arrays, so trust the source count rather than the exported hints.
      const stride = Math.max(1, Math.ceil(count / maxArrows));
      const arrows = [];
      let maximum = 0;
      for (let index = 0; index < count; index += 1) {
        if (!finiteNumber(theta[index]) || !finiteNumber(r[index])) continue;
        observed = Math.max(observed, Math.abs(r[index]));
        if (u === null || v === null) continue;
        const uValue = u[index];
        const vValue = v[index];
        if (!finiteNumber(uValue) || !finiteNumber(vValue)) continue;
        const raw = Math.sqrt(uValue * uValue + vValue * vValue);
        const magnitude = normalize && raw > 0 ? 1 : raw;
        maximum = Math.max(maximum, magnitude);
        if (raw > 1e-12 && index % stride === 0) {
          arrows.push({
            index: index + 1, theta: theta[index], r: r[index],
            u: uValue, v: vValue, raw, magnitude,
          });
        }
      }
      let scale = finiteNumber(item.scale) && item.scale > 0 ? item.scale : null;
      const autoScale = scale === null;
      if (scale === null && finiteNumber(item.resolved_scale)
        && item.resolved_scale > 0) {
        scale = item.resolved_scale;
      }
      if (scale === null) scale = maximum > 0 ? QUIVER_AUTO_LENGTH / maximum : 1;
      const pivot = item.pivot === "middle" || item.pivot === "tip"
        ? item.pivot : "tail";
      collected.push({
        kind: "quiver",
        arrows,
        count,
        drawn: arrows.length,
        color,
        alpha,
        linewidth: finiteNumber(style.linewidth)
          ? Math.max(0, style.linewidth) : QUIVER_DEFAULT_LINEWIDTH,
        head: finiteNumber(style.head) ? Math.max(0, style.head)
          : QUIVER_DEFAULT_HEAD,
        pivot,
        normalize,
        maxArrows,
        stride,
        scale,
        autoScale,
        label: typeof style.label === "string" ? style.label : null,
      });
    } else if (item.kind === "streamplot") {
      // luaplotlib integrates the field and exports finished theta/r
      // polylines with one mid-line arrow each.  Copy, filter, and project
      // them here so the browser matches the Lua renderers.
      const head = finiteNumber(item.head) ? Math.max(0, item.head)
        : (finiteNumber(style.head) ? Math.max(0, style.head) : STREAM_DEFAULT_HEAD);
      const drawArrows = item.arrows !== false && head > 0;
      const lines = [];
      let totalPoints = 0;
      let totalArrows = 0;
      const sourceLines = array(item.lines);
      for (let lineIndex = 0; lineIndex < sourceLines.length; lineIndex += 1) {
        const line = sourceLines[lineIndex];
        if (!line || typeof line !== "object") continue;
        const lineTheta = array(line.theta);
        const lineR = array(line.r);
        const linePoints = [];
        const lineCount = Math.min(lineTheta.length, lineR.length);
        for (let index = 0; index < lineCount; index += 1) {
          if (!finiteNumber(lineTheta[index]) || !finiteNumber(lineR[index])) continue;
          observed = Math.max(observed, Math.abs(lineR[index]));
          linePoints.push({ theta: lineTheta[index], r: lineR[index] });
        }
        const lineArrows = [];
        if (drawArrows) {
          for (const arrow of array(line.arrows)) {
            if (!arrow || !finiteNumber(arrow.theta) || !finiteNumber(arrow.r)
              || !finiteNumber(arrow.angle)) continue;
            lineArrows.push({
              theta: arrow.theta, r: arrow.r, angle: arrow.angle,
            });
          }
        }
        if (linePoints.length >= 2) {
          totalPoints += linePoints.length;
          totalArrows += lineArrows.length;
          lines.push({
            index: Number.isInteger(line.index) ? line.index : lineIndex + 1,
            points: linePoints,
            arrows: lineArrows,
          });
        }
      }
      for (const value of array(r)) {
        if (finiteNumber(value)) observed = Math.max(observed, Math.abs(value));
      }
      const density = finiteNumber(item.density)
        ? Math.max(0.1, Math.min(10, item.density)) : STREAM_DEFAULT_DENSITY;
      const requestedStep = finiteNumber(item.step) && item.step > 0
        ? item.step : null;
      let step = finiteNumber(item.resolved_step) && item.resolved_step > 0
        ? item.resolved_step : requestedStep;
      const stepMode = item.step_mode === "auto" ? "auto"
        : item.step_mode === "explicit" ? "explicit"
          : (requestedStep === null ? "auto" : "explicit");
      if (step === null) {
        const span = r.length > 1 ? r[r.length - 1] - r[0]
          : (r.length > 0 ? r[r.length - 1] : 0);
        step = span > 0 ? span / 25 : 1;
      }
      const periodic = typeof item.periodic === "boolean" ? item.periodic
        : (theta.length >= 2 && theta[theta.length - 1] - theta[0] >= TAU - 1e-9);
      const linewidth = finiteNumber(style.linewidth)
        ? Math.max(0, style.linewidth)
        : (finiteNumber(item.linewidth) ? Math.max(0, item.linewidth)
          : STREAM_DEFAULT_LINEWIDTH);
      collected.push({
        kind: "streamplot",
        lines,
        cols: theta.length,
        rows: r.length,
        lineCount: lines.length,
        pointCount: totalPoints,
        arrowCount: totalArrows,
        color,
        alpha,
        linewidth,
        head,
        arrows: item.arrows !== false,
        density,
        step,
        stepMode,
        maxSteps: finiteInteger(item.max_steps, 10) ?? STREAM_DEFAULT_MAX_STEPS,
        maxLines: finiteInteger(item.max_lines, 1) ?? STREAM_DEFAULT_MAX_LINES,
        maxPoints: finiteInteger(item.max_points, 100) ?? STREAM_DEFAULT_MAX_POINTS,
        periodic,
        truncated: item.truncated === true,
        label: typeof style.label === "string" ? style.label : null,
      });
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
  const { series, observed: seriesObserved } = collectPolar(scene);
  const heatmaps = collectHeatmaps(polar);
  const contours = collectContours(polar);
  let observed = seriesObserved;
  for (const heatmap of heatmaps) observed = Math.max(observed, heatmap.rmax);
  for (const contour of contours) observed = Math.max(observed, contour.rmax);
  return {
    polar,
    series,
    heatmaps,
    contours,
    colorbar: collectColorbar(polar, heatmaps),
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

// Screen-space arrow geometry for one collected quiver series.  Mirrors
// Polar.quiver_arrows in notebook/polar.lua: `u` points toward increasing data
// theta, `v` outward along the radius, and glyph lengths are SVG user units.
export function quiverArrows(quiver, cx, cy, radius, rmax, thetaZero, direction) {
  const arrows = [];
  if (!quiver || typeof quiver !== "object") return arrows;
  const safeRmax = finiteNumber(rmax) && rmax > 0 ? rmax : 1;
  const pivot = quiver.pivot === "middle" ? 0.5
    : quiver.pivot === "tip" ? 1 : 0;
  const scale = finiteNumber(quiver.scale) ? quiver.scale : 1;
  const head = finiteNumber(quiver.head) ? quiver.head : 0;
  for (const arrow of array(quiver.arrows)) {
    const raw = finiteNumber(arrow.raw)
      ? arrow.raw : Math.sqrt(arrow.u * arrow.u + arrow.v * arrow.v);
    if (!(raw > 1e-12)) continue;
    const magnitude = quiver.normalize ? 1 : raw;
    const display = thetaZero + direction * arrow.theta;
    const cosine = Math.cos(display);
    const sine = Math.sin(display);
    const dx = arrow.v * cosine - direction * arrow.u * sine;
    const dy = -arrow.v * sine - direction * arrow.u * cosine;
    const ux = dx / raw;
    const uy = dy / raw;
    const length = magnitude * scale;
    const point = projectPolar(cx, cy, radius, safeRmax, thetaZero,
      direction, arrow.theta, arrow.r);
    const tailX = point.x - ux * length * pivot;
    const tailY = point.y - uy * length * pivot;
    const tipX = tailX + ux * length;
    const tipY = tailY + uy * length;
    const arrowHead = Math.min(head, length);
    const neckX = tipX - ux * arrowHead;
    const neckY = tipY - uy * arrowHead;
    const half = arrowHead * 0.45;
    const px = -uy * half;
    const py = ux * half;
    let angle = (Math.atan2(dy, dx) * 180) / Math.PI;
    if (angle === 0) angle = 0;
    arrows.push({
      index: arrow.index,
      theta: arrow.theta,
      r: arrow.r,
      u: arrow.u,
      v: arrow.v,
      raw,
      magnitude,
      angle,
      length,
      x: point.x,
      y: point.y,
      tailX,
      tailY,
      tipX,
      tipY,
      neckX,
      neckY,
      headX1: tipX,
      headY1: tipY,
      headX2: neckX + px,
      headY2: neckY + py,
      headX3: neckX - px,
      headY3: neckY - py,
      shaft: quiver.linewidth > 0 && length - arrowHead > 1e-9,
      headed: arrowHead > 1e-9,
    });
  }
  return arrows;
}

// Screen geometry for one collected streamplot series.  Mirrors
// Polar.stream_lines in notebook/polar.lua: project each integrated polyline
// point and rebuild the mid-line arrow triangle from the exported
// screen-space angle.
export function streamLines(stream, cx, cy, radius, rmax, thetaZero, direction) {
  const lines = [];
  if (!stream || typeof stream !== "object") return lines;
  rmax = finiteNumber(rmax) && rmax > 0 ? rmax : 1;
  const head = finiteNumber(stream.head) ? Math.max(0, stream.head) : 0;
  const drawArrows = stream.arrows !== false && head > 0;
  const half = head * 0.45;
  for (const line of array(stream.lines)) {
    if (!line || typeof line !== "object") continue;
    const points = [];
    for (const point of array(line.points)) {
      const projected = projectPolar(cx, cy, radius, rmax, thetaZero, direction,
        point.theta, point.r);
      points.push({
        x: projected.x, y: projected.y, theta: point.theta, r: point.r,
      });
    }
    const arrows = [];
    if (drawArrows) {
      for (const arrow of array(line.arrows)) {
        const projected = projectPolar(cx, cy, radius, rmax, thetaZero,
          direction, arrow.theta, arrow.r);
        const radians = (arrow.angle * Math.PI) / 180;
        const ux = Math.cos(radians);
        const uy = Math.sin(radians);
        const px = -uy * half;
        const py = ux * half;
        const tipX = projected.x + ux * head * 0.5;
        const tipY = projected.y + uy * head * 0.5;
        const neckX = projected.x - ux * head * 0.5;
        const neckY = projected.y - uy * head * 0.5;
        arrows.push({
          index: arrow.index,
          theta: arrow.theta,
          r: arrow.r,
          angle: arrow.angle,
          x: projected.x,
          y: projected.y,
          tipX,
          tipY,
          headX1: tipX,
          headY1: tipY,
          headX2: neckX + px,
          headY2: neckY + py,
          headX3: neckX - px,
          headY3: neckY - py,
        });
      }
    }
    if (points.length >= 2) {
      lines.push({ index: line.index ?? lines.length + 1, points, arrows });
    }
  }
  return lines;
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

// ---------------------------------------------------------------------------
// Polar fields: heatmaps, contours, and the colourbar.  These helpers mirror
// notebook/polar.lua; webapp/tests/fixtures/polar-parity.json pins the shared
// numbers so the Lua, SVG, and Canvas renderers cannot drift silently.

export const COLORBAR_WIDTH = 16;
export const COLORBAR_GAP = 16;
export const COLORBAR_MARGIN = 56;
export const COLORBAR_STEPS = 40;
export const FULL_TURN_PARTS = 48;
export const CONTOUR_MAX_STEPS = 64;
export const CONTOUR_LABEL_SCALE = 5.5;

// A large field is painted as at most this many block cells.  Keep this bound
// in sync with Polar.HEATMAP_CELL_LIMIT in notebook/polar.lua.
export const HEATMAP_CELL_LIMIT = 4096;

// Viridis-like anchors copied from luaplotlib's colour helper.  Channel
// rounding must match notebook/polar.lua exactly.
export const HEAT_ANCHORS = [
  [0.267, 0.005, 0.329],
  [0.188, 0.407, 0.554],
  [0.128, 0.567, 0.551],
  [0.369, 0.789, 0.383],
  [0.993, 0.906, 0.144],
];

function clamp(value, minimum, maximum) {
  if (value < minimum) return minimum;
  if (value > maximum) return maximum;
  return value;
}

function clamp01(value) {
  if (!finiteNumber(value)) return 1;
  return clamp(value, 0, 1);
}

function finiteInteger(value, minimum) {
  return finiteNumber(value) && value >= minimum && Number.isInteger(value)
    ? value : null;
}

function hexChannel(value) {
  return Math.round(value).toString(16).padStart(2, "0");
}

export function heatColor(value, vmin, vmax) {
  if (!finiteNumber(value)) value = vmin;
  if (!finiteNumber(vmin) || !finiteNumber(vmax) || vmax <= vmin) {
    return "#440154";
  }
  const t = clamp((value - vmin) / (vmax - vmin), 0, 1);
  const scaled = t * (HEAT_ANCHORS.length - 1);
  let index = Math.floor(scaled);
  if (index >= HEAT_ANCHORS.length - 1) index = HEAT_ANCHORS.length - 2;
  const fraction = scaled - index;
  const a = HEAT_ANCHORS[index];
  const b = HEAT_ANCHORS[index + 1];
  const channel = (left, right) => Math.floor((left + (right - left) * fraction) * 255 + 0.5);
  return `#${hexChannel(channel(a[0], b[0]))}${hexChannel(channel(a[1], b[1]))}${hexChannel(channel(a[2], b[2]))}`;
}

// Compact colourbar labels.  Mirrors Polar.compact_number in Lua.
export function compactNumber(value) {
  if (!finiteNumber(value)) return null;
  if (value === 0) return "0";
  const magnitude = Math.abs(value);
  if (magnitude >= 1e-4 && magnitude < 1e5) {
    return String(Number(value.toPrecision(3)));
  }
  const [mantissa, exponent] = value.toExponential(2).split("e");
  return `${Number(mantissa)}e${Number(exponent)}`;
}

// Choose the row/column strides used to paint a heatmap.  A field at or below
// `limit` keeps every cell.  Larger fields are sampled so the painted block
// count stays at or below the limit; each painted block covers the source
// cells it replaces.  This mirrors Polar.heatmap_sampling in Lua.
export function heatmapSampling(rows, cols, limit = HEATMAP_CELL_LIMIT) {
  limit = finiteInteger(limit, 1) ?? HEATMAP_CELL_LIMIT;
  rows = finiteInteger(rows, 1) ?? 1;
  cols = finiteInteger(cols, 1) ?? 1;
  if (rows <= limit && cols <= Math.floor(limit / rows)) {
    return {
      rowStep: 1, colStep: 1,
      sampledRows: rows, sampledCols: cols,
      count: rows * cols, sampled: false,
    };
  }
  let target = (limit * rows) / cols;
  if (target > limit) target = limit;
  if (target < 1) target = 1;
  let rowTarget = Math.floor(Math.sqrt(target));
  if (rowTarget < 1) rowTarget = 1;
  if (rowTarget > rows) rowTarget = rows;
  let colTarget = Math.floor(limit / rowTarget);
  if (colTarget > cols) colTarget = cols;
  if (colTarget < 1) colTarget = 1;
  let rowStep = Math.ceil(rows / rowTarget);
  let colStep = Math.ceil(cols / colTarget);
  for (let pass = 0; pass < 3; pass += 1) {
    const sampledRows = Math.ceil(rows / rowStep);
    const maxCols = Math.max(1, Math.floor(limit / sampledRows));
    const nextCols = Math.min(cols, maxCols);
    colStep = Math.ceil(cols / nextCols);
    const sampledCols = Math.ceil(cols / colStep);
    const maxRows = Math.max(1, Math.floor(limit / sampledCols));
    const nextRows = Math.min(rows, maxRows);
    rowStep = Math.ceil(rows / nextRows);
  }
  const sampledRows = Math.ceil(rows / rowStep);
  const sampledCols = Math.ceil(cols / colStep);
  return {
    rowStep, colStep, sampledRows, sampledCols,
    count: sampledRows * sampledCols, sampled: true,
  };
}

export function collectHeatmaps(polar) {
  const heatmaps = [];
  for (const item of array(polar && polar.heatmaps)) {
    if (!item || typeof item !== "object") continue;
    const rows = finiteInteger(item.rows, 1);
    const cols = finiteInteger(item.cols, 1);
    if (!rows || !cols || !Array.isArray(item.values)) continue;
    const sampling = heatmapSampling(rows, cols);
    const hasVmin = finiteNumber(item.vmin);
    const hasVmax = finiteNumber(item.vmax);
    let minimum = null;
    let maximum = null;
    if (!(hasVmin && hasVmax)) {
      for (let row = 0; row < rows; row += 1) {
        const source = Array.isArray(item.values[row]) ? item.values[row] : [];
        for (let col = 0; col < cols; col += 1) {
          const value = source[col];
          if (finiteNumber(value)) {
            if (minimum === null || value < minimum) minimum = value;
            if (maximum === null || value > maximum) maximum = value;
          }
        }
      }
    }
    const cells = [];
    if (sampling.sampled) {
      for (let sampleRow = 0; sampleRow < sampling.sampledRows; sampleRow += 1) {
        let sourceRow = sampleRow * sampling.rowStep
          + Math.floor((sampling.rowStep - 1) / 2);
        if (sourceRow >= rows) sourceRow = rows - 1;
        const source = Array.isArray(item.values[sourceRow])
          ? item.values[sourceRow] : [];
        const copied = [];
        for (let sampleCol = 0; sampleCol < sampling.sampledCols; sampleCol += 1) {
          let sourceCol = sampleCol * sampling.colStep
            + Math.floor((sampling.colStep - 1) / 2);
          if (sourceCol >= cols) sourceCol = cols - 1;
          const value = source[sourceCol];
          copied.push(finiteNumber(value) ? value : null);
        }
        cells.push(copied);
      }
    } else {
      for (let row = 0; row < rows; row += 1) {
        const source = Array.isArray(item.values[row]) ? item.values[row] : [];
        const copied = [];
        for (let col = 0; col < cols; col += 1) {
          const value = source[col];
          copied.push(finiteNumber(value) ? value : null);
        }
        cells.push(copied);
      }
    }
    let vmin = hasVmin ? item.vmin : minimum;
    let vmax = hasVmax ? item.vmax : maximum;
    if (vmin === null) vmin = 0;
    if (vmax === null || vmax <= vmin) vmax = vmin + 1;
    const rmin = finiteNumber(item.rmin) ? Math.max(0, item.rmin) : 0;
    let rmax = finiteNumber(item.rmax) ? item.rmax : rows;
    if (rmax <= rmin) rmax = rmin + 1;
    const thetaMin = finiteNumber(item.theta_min) ? item.theta_min : 0;
    let thetaMax = finiteNumber(item.theta_max) ? item.theta_max : thetaMin + TAU;
    if (thetaMax <= thetaMin) thetaMax = thetaMin + TAU;
    if (thetaMax - thetaMin > TAU) thetaMax = thetaMin + TAU;
    heatmaps.push({
      kind: "heatmap",
      rows, cols, values: cells, vmin, vmax, rmin, rmax,
      thetaMin, thetaMax,
      alpha: clamp01(item.alpha),
      label: typeof item.label === "string" ? item.label : null,
      colorbar: item.colorbar === true,
      rowStep: sampling.rowStep,
      colStep: sampling.colStep,
      sampled: sampling.sampled,
      sampledCells: sampling.count,
    });
  }
  return heatmaps;
}

export function collectContours(polar) {
  const contours = [];
  const source = array(polar && polar.contours);
  for (let index = 0; index < source.length; index += 1) {
    const item = source[index];
    if (!item || typeof item !== "object" || !Array.isArray(item.levels)) continue;
    const style = item.style && typeof item.style === "object" ? item.style : {};
    const rmin = finiteNumber(item.rmin) ? Math.max(0, item.rmin) : 0;
    let rmax = finiteNumber(item.rmax) ? item.rmax : rmin + 1;
    if (rmax <= rmin) rmax = rmin + 1;
    const thetaMin = finiteNumber(item.theta_min) ? item.theta_min : 0;
    let thetaMax = finiteNumber(item.theta_max) ? item.theta_max : thetaMin + TAU;
    if (thetaMax <= thetaMin) thetaMax = thetaMin + TAU;
    if (thetaMax - thetaMin > TAU) thetaMax = thetaMin + TAU;
    const levels = [];
    for (const level of item.levels) {
      if (!level || typeof level !== "object" || !finiteNumber(level.level)
        || !Array.isArray(level.segments)) continue;
      const segments = [];
      for (const segment of level.segments) {
        if (Array.isArray(segment) && segment.length >= 4
          && segment.slice(0, 4).every(finiteNumber)) {
          segments.push(segment.slice(0, 4));
        }
      }
      if (segments.length) levels.push({ level: level.level, segments });
    }
    if (!levels.length) continue;
    let linestyle = style.linestyle;
    if (linestyle !== "dashed" && linestyle !== "dotted" && linestyle !== "none") {
      linestyle = "solid";
    }
    let color = validColor(style.color);
    if (color === null) color = PALETTE[index % PALETTE.length];
    contours.push({
      kind: "contour",
      rows: finiteInteger(item.rows, 1),
      cols: finiteInteger(item.cols, 1),
      rmin, rmax, thetaMin, thetaMax, levels,
      labels: item.labels === true,
      style: {
        color,
        linewidth: finiteNumber(style.linewidth) ? Math.max(0, style.linewidth) : 1.5,
        alpha: clamp01(style.alpha),
        linestyle,
        label: typeof style.label === "string" ? style.label : null,
      },
    });
  }
  return contours;
}

export function collectColorbar(polar, heatmaps) {
  const item = polar && typeof polar === "object"
    && polar.colorbar && typeof polar.colorbar === "object"
    ? polar.colorbar : null;
  let source = item;
  if (source === null) {
    for (const heatmap of heatmaps || []) {
      if (heatmap.colorbar) { source = heatmap; break; }
    }
  }
  if (source === null) return null;
  const vmin = finiteNumber(source.vmin) ? source.vmin : null;
  const vmax = finiteNumber(source.vmax) ? source.vmax : null;
  if (vmin === null || vmax === null || vmax <= vmin) return null;
  let ticks = [];
  if (Array.isArray(source.ticks) && source.ticks.length >= 2) {
    ticks = source.ticks.filter(finiteNumber);
  }
  if (ticks.length < 2) {
    ticks = [];
    for (let index = 0; index < 3; index += 1) {
      ticks.push(vmin + ((vmax - vmin) * index) / 2);
    }
  }
  return {
    orientation: source.orientation === "horizontal" ? "horizontal" : "vertical",
    vmin, vmax, ticks,
    label: typeof source.label === "string" && source.label !== "" ? source.label : null,
  };
}

export function frameLayout(left, top, right, bottom, hasColorbar) {
  const plotW = Math.max(1, right - left);
  const plotH = Math.max(1, bottom - top);
  const fieldW = Math.max(1, plotW - (hasColorbar ? COLORBAR_MARGIN : 0));
  return {
    cx: left + fieldW / 2,
    cy: top + plotH / 2,
    radius: frameRadius(fieldW, plotH),
  };
}

export function colorbarLayout(cx, cy, radius) {
  const width = COLORBAR_WIDTH;
  const height = radius * 1.7;
  return { x: cx + radius + COLORBAR_GAP, y: cy - height / 2, width, height };
}

export function colorbarTicks(colorbar) {
  const ticks = [];
  if (!colorbar || typeof colorbar !== "object") return ticks;
  const span = colorbar.vmax - colorbar.vmin;
  if (span <= 0) return ticks;
  for (const value of array(colorbar.ticks)) {
    if (finiteNumber(value)) {
      ticks.push({
        value,
        label: compactNumber(value),
        fraction: clamp((value - colorbar.vmin) / span, 0, 1),
      });
    }
  }
  return ticks;
}

export function colorbarSteps(colorbar, count = COLORBAR_STEPS) {
  const steps = [];
  if (!colorbar || typeof colorbar !== "object") return steps;
  const span = colorbar.vmax - colorbar.vmin;
  if (span <= 0 || count <= 0) return steps;
  for (let index = 1; index <= count; index += 1) {
    const value = colorbar.vmax - span * ((index - 0.5) / count);
    steps.push({
      value,
      color: heatColor(value, colorbar.vmin, colorbar.vmax),
      y0: (index - 1) / count,
      y1: index / count,
    });
  }
  return steps;
}

// Project every painted matrix block into an annular sector (or a full disc /
// split ring).  Large fields are sampled into blocks by heatmapSampling; each
// block spans the source rows/columns it replaces.  Cells keep source
// row/column indices plus rowSpan/colSpan for parity with the export.
export function heatmapCells(heatmap, cx, cy, radius, rmax, thetaZero, direction) {
  const cells = [];
  if (!heatmap || typeof heatmap !== "object") return cells;
  rmax = finiteNumber(rmax) && rmax > 0 ? rmax : 1;
  const sampling = heatmapSampling(heatmap.rows, heatmap.cols);
  const rowStep = Math.max(1, Math.min(
    finiteInteger(heatmap.rowStep, 1) ?? sampling.rowStep, heatmap.rows));
  const colStep = Math.max(1, Math.min(
    finiteInteger(heatmap.colStep, 1) ?? sampling.colStep, heatmap.cols));
  const sampledValues = heatmap.sampled === true;
  const outer = (radius * Math.min(heatmap.rmax, rmax)) / rmax;
  let inner = (radius * Math.max(0, heatmap.rmin)) / rmax;
  if (inner > outer) inner = outer;
  const span = heatmap.thetaMax - heatmap.thetaMin;
  const colSpan = span / heatmap.cols;
  let rowIndex = 0;
  for (let row = 1; row <= heatmap.rows; row += rowStep) {
    rowIndex += 1;
    const rowEnd = Math.min(heatmap.rows, row + rowStep - 1);
    const rowInner = inner + ((outer - inner) * (row - 1)) / heatmap.rows;
    const rowOuter = inner + ((outer - inner) * rowEnd) / heatmap.rows;
    let colIndex = 0;
    for (let col = 1; col <= heatmap.cols; col += colStep) {
      colIndex += 1;
      const colEnd = Math.min(heatmap.cols, col + colStep - 1);
      let value;
      if (sampledValues) {
        value = heatmap.values[rowIndex - 1]?.[colIndex - 1];
      } else {
        const sampleRow = Math.min(rowEnd,
          row + Math.floor((rowStep - 1) / 2));
        const sampleCol = Math.min(colEnd,
          col + Math.floor((colStep - 1) / 2));
        value = heatmap.values[sampleRow - 1]?.[sampleCol - 1];
      }
      if (!finiteNumber(value)) value = heatmap.vmin;
      const theta0 = heatmap.thetaMin + colSpan * (col - 1);
      const theta1 = heatmap.thetaMin + colSpan * colEnd;
      const startAngle = thetaZero + direction * theta0;
      const endAngle = thetaZero + direction * theta1;
      const cell = {
        row, col,
        rowSpan: rowEnd - row + 1,
        colSpan: colEnd - col + 1,
        value,
        color: heatColor(value, heatmap.vmin, heatmap.vmax),
        alpha: heatmap.alpha,
        innerRadius: rowInner,
        outerRadius: rowOuter,
        startAngle,
        endAngle,
      };
      const cellSpan = Math.abs(endAngle - startAngle);
      if (cellSpan >= TAU - 1e-9) {
        if (rowInner <= 0.0005) {
          cell.fullDisc = true;
          cell.parts = [];
        } else {
          cell.parts = [];
          const step = (endAngle - startAngle) / FULL_TURN_PARTS;
          for (let part = 1; part <= FULL_TURN_PARTS; part += 1) {
            const partStart = startAngle + step * (part - 1);
            cell.parts.push({ startAngle: partStart, endAngle: partStart + step });
          }
        }
      } else {
        cell.parts = [{ startAngle, endAngle }];
      }
      cells.push(cell);
    }
  }
  return cells;
}

export function contourSegmentPoints(contour, segment, cx, cy, radius, rmax, thetaZero, direction) {
  const points = [];
  if (!Array.isArray(segment) || segment.length < 4 || !segment.slice(0, 4).every(finiteNumber)) {
    return points;
  }
  rmax = finiteNumber(rmax) && rmax > 0 ? rmax : 1;
  const [theta0, radius0, theta1, radius1] = segment;
  const angular = Math.abs(theta1 - theta0);
  const radial = Math.abs(radius1 - radius0) / rmax;
  let steps = Math.max(2, Math.ceil(angular / (Math.PI / 48)),
    Math.ceil((radial * radius) / 5));
  if (steps > CONTOUR_MAX_STEPS) steps = CONTOUR_MAX_STEPS;
  for (let step = 0; step <= steps; step += 1) {
    const t = step / steps;
    const theta = theta0 + (theta1 - theta0) * t;
    const value = radius0 + (radius1 - radius0) * t;
    const point = projectPolar(cx, cy, radius, rmax, thetaZero, direction, theta, value);
    points.push({ x: point.x, y: point.y });
  }
  return points;
}

export function contourLabel(contour, level, cx, cy, radius, rmax, thetaZero, direction) {
  if (!contour || contour.labels !== true) return null;
  if (!level || !finiteNumber(level.level) || !Array.isArray(level.segments)) return null;
  let best = null;
  let bestRadius = -1;
  for (const segment of level.segments) {
    if (!Array.isArray(segment)) continue;
    const midTheta = (segment[0] + segment[2]) / 2;
    const midRadius = (segment[1] + segment[3]) / 2;
    if (Math.abs(midRadius) > bestRadius) {
      best = [midTheta, midRadius];
      bestRadius = Math.abs(midRadius);
    }
  }
  if (best === null) return null;
  const text = compactNumber(level.level);
  if (text === null) return null;
  const projected = projectPolar(cx, cy, radius, rmax, thetaZero, direction, best[0], best[1]);
  let { x, y } = projected;
  const dx = x - cx;
  const dy = y - cy;
  const distance = Math.sqrt(dx * dx + dy * dy);
  const margin = (text.length * CONTOUR_LABEL_SCALE) / 2 + 4;
  const limit = radius - margin;
  if (limit > 0 && distance > limit) {
    x = cx + (dx / distance) * limit;
    y = cy + (dy / distance) * limit;
  }
  return { x, y, text };
}
