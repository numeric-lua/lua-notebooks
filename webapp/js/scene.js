import {
  BAR_SAMPLE_LIMIT, LINE_SAMPLE_LIMIT, PALETTE as SCENE_PALETTE,
  SCATTER_SAMPLE_LIMIT, barSectors, colorbarLayout, colorbarSteps,
  colorbarTicks, contourLabel, contourSegmentPoints, finiteNumber,
  frameLayout, heatmapCells, pointRadius, polarRings, polarSpokes,
  projectPolar, quiverArrows, radiusLabel, resolvePolar, ringLabelPosition,
  sampleStep, thetaLabel, thetaLabelPosition, validColor,
} from "./polar.js";

const scenes = new WeakMap();
const TAU = Math.PI * 2;

function cssSize(canvas) {
  const rect = canvas.getBoundingClientRect();
  return { width: Math.max(240, rect.width || 600), height: Math.max(120, rect.height || 230) };
}

function arrayOf(value) {
  return Array.isArray(value) ? value : [];
}

// Normalize the Cartesian IR into the same point/bar shapes the export and
// live renderers use.  Filtering non-finite values and copying coefficients
// keeps the draw loops simple and makes the sample caps meaningful.
function collectCartesian(scene) {
  const collected = [];
  let paletteIndex = 0;
  for (const item of arrayOf(scene && scene.series)) {
    if (!item || typeof item !== "object") continue;
    const style = item.style && typeof item.style === "object" ? item.style : {};
    let color = validColor(style.color);
    if (color === null) {
      paletteIndex += 1;
      color = SCENE_PALETTE[(paletteIndex - 1) % SCENE_PALETTE.length];
    }
    const alpha = finiteNumber(style.alpha) ? style.alpha : 1;
    if (item.kind === "bar") {
      const xs = arrayOf(item.x);
      const ys = arrayOf(item.y);
      const width = finiteNumber(item.width) ? Math.max(0.001, item.width) : 0.7;
      const bars = [];
      for (let index = 0; index < Math.min(xs.length, ys.length); index += 1) {
        if (finiteNumber(xs[index]) && finiteNumber(ys[index])) {
          bars.push({ x: xs[index], y: ys[index], width });
        }
      }
      if (bars.length) collected.push({ kind: "bar", bars, color, alpha });
    } else if (item.kind === "hist") {
      const edges = arrayOf(item.edges);
      const counts = arrayOf(item.counts);
      const bars = [];
      for (let index = 0; index < Math.min(edges.length - 1, counts.length); index += 1) {
        if (finiteNumber(edges[index]) && finiteNumber(edges[index + 1]) && finiteNumber(counts[index])) {
          bars.push({
            x: (edges[index] + edges[index + 1]) / 2,
            y: counts[index],
            width: edges[index + 1] - edges[index],
          });
        }
      }
      if (bars.length) collected.push({ kind: "hist", bars, color, alpha });
    } else if (item.kind === "line" || item.kind === "scatter" || item.kind === undefined) {
      const xs = arrayOf(item.x);
      const ys = arrayOf(item.y);
      const points = [];
      for (let index = 0; index < Math.min(xs.length, ys.length); index += 1) {
        if (finiteNumber(xs[index]) && finiteNumber(ys[index])) {
          points.push({ x: xs[index], y: ys[index] });
        }
      }
      if (points.length) {
        collected.push({
          kind: item.kind === "scatter" ? "scatter" : "line",
          points,
          color,
          alpha,
          width: finiteNumber(style.width) ? style.width : null,
          radius: finiteNumber(style.radius) ? style.radius
            : finiteNumber(style.markersize) ? style.markersize : null,
        });
      }
    }
  }
  return collected;
}

function cartesianBounds(scene, collected) {
  let xmin = Infinity, xmax = -Infinity, ymin = Infinity, ymax = -Infinity;
  const include = (x, y) => {
    if (!finiteNumber(x) || !finiteNumber(y)) return;
    xmin = Math.min(xmin, x); xmax = Math.max(xmax, x);
    ymin = Math.min(ymin, y); ymax = Math.max(ymax, y);
  };
  for (const series of collected) {
    if (series.points) {
      for (const point of series.points) include(point.x, point.y);
    } else if (series.bars) {
      for (const bar of series.bars) {
        include(bar.x - bar.width / 2, 0);
        include(bar.x + bar.width / 2, bar.y);
      }
    }
  }
  if (!Number.isFinite(xmin)) { xmin = 0; xmax = 1; ymin = 0; ymax = 1; }
  const xlim = Array.isArray(scene.xlim) ? scene.xlim : null;
  const ylim = Array.isArray(scene.ylim) ? scene.ylim : null;
  if (xlim && finiteNumber(xlim[0]) && finiteNumber(xlim[1]) && xlim[0] < xlim[1]) {
    xmin = xlim[0]; xmax = xlim[1];
  }
  if (ylim && finiteNumber(ylim[0]) && finiteNumber(ylim[1]) && ylim[0] < ylim[1]) {
    ymin = ylim[0]; ymax = ylim[1];
  }
  if (xmax === xmin) { xmax += 1; xmin -= 1; }
  if (ymax === ymin) { ymax += 1; ymin -= 1; }
  const xpad = (xmax - xmin) * 0.05 || 0.1;
  const ypad = (ymax - ymin) * 0.08 || 0.1;
  return { xmin: xmin - xpad, xmax: xmax + xpad, ymin: ymin - ypad, ymax: ymax + ypad };
}

function drawChart(canvas, scene, ctx) {
  const { width, height } = cssSize(canvas);
  const margin = { left: 44, right: 16, top: scene.title ? 32 : 16, bottom: 34 };
  const plotW = width - margin.left - margin.right;
  const plotH = height - margin.top - margin.bottom;
  const collected = collectCartesian(scene);
  const b = cartesianBounds(scene, collected);
  const sx = (x) => margin.left + ((x - b.xmin) / (b.xmax - b.xmin)) * plotW;
  const sy = (y) => margin.top + plotH - ((y - b.ymin) / (b.ymax - b.ymin)) * plotH;

  ctx.save();
  ctx.fillStyle = "#0c1019";
  ctx.fillRect(0, 0, width, height);
  ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
  ctx.textBaseline = "middle";

  if (scene.title) {
    ctx.fillStyle = "#dfe5f4";
    ctx.font = "600 13px ui-sans-serif, system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(String(scene.title), margin.left + plotW / 2, 16);
    ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
  }

  if (scene.grid !== false) {
    ctx.strokeStyle = "#1d2433";
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i += 1) {
      const y = margin.top + (plotH * i) / 4;
      const x = margin.left + (plotW * i) / 4;
      ctx.beginPath(); ctx.moveTo(margin.left, y); ctx.lineTo(margin.left + plotW, y); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(x, margin.top); ctx.lineTo(x, margin.top + plotH); ctx.stroke();
    }
  }

  ctx.strokeStyle = "#42506a";
  ctx.beginPath();
  ctx.moveTo(margin.left, margin.top);
  ctx.lineTo(margin.left, margin.top + plotH);
  ctx.lineTo(margin.left + plotW, margin.top + plotH);
  ctx.stroke();

  ctx.fillStyle = "#7e879b";
  ctx.textAlign = "right";
  for (let i = 0; i <= 4; i += 1) {
    const value = b.ymin + ((b.ymax - b.ymin) * i) / 4;
    const y = sy(value);
    ctx.fillText(formatTick(value), margin.left - 7, y);
  }
  ctx.textAlign = "center";
  const categories = Array.isArray(scene.category_ticks) ? scene.category_ticks : null;
  if (categories) {
    for (const tick of categories) {
      if (tick && finiteNumber(tick.position)) {
        ctx.fillText(String(tick.label ?? ""), sx(tick.position), margin.top + plotH + 16);
      }
    }
  } else {
    for (let i = 0; i <= 4; i += 1) {
      const value = b.xmin + ((b.xmax - b.xmin) * i) / 4;
      const x = sx(value);
      ctx.fillText(formatTick(value), x, margin.top + plotH + 16);
    }
  }

  const baseline = Math.max(b.ymin, Math.min(0, b.ymax));
  for (const series of collected) {
    ctx.save();
    ctx.globalAlpha = Math.max(0, Math.min(1, series.alpha));
    ctx.strokeStyle = series.color;
    ctx.fillStyle = series.color;
    if (series.bars) {
      const zero = sy(baseline);
      for (const bar of series.bars) {
        const x0 = sx(bar.x - bar.width / 2);
        const x1 = sx(bar.x + bar.width / 2);
        const y = sy(bar.y);
        const left = Math.min(x0, x1);
        const barWidth = Math.max(1, Math.abs(x1 - x0));
        ctx.fillRect(left, Math.min(y, zero), barWidth, Math.abs(zero - y));
      }
    } else if (series.points) {
      if (series.kind === "scatter") {
        const radius = Math.max(1.5, series.radius ?? 3);
        const step = sampleStep(series.points.length, SCATTER_SAMPLE_LIMIT);
        for (let index = 0; index < series.points.length; index += step) {
          const point = series.points[index];
          ctx.beginPath();
          ctx.arc(sx(point.x), sy(point.y), radius, 0, TAU);
          ctx.fill();
        }
      } else {
        ctx.lineWidth = Math.max(0.1, series.width ?? 1.6);
        const step = sampleStep(series.points.length, LINE_SAMPLE_LIMIT);
        ctx.beginPath();
        let started = false;
        for (let index = 0; index < series.points.length; index += step) {
          const point = series.points[index];
          const x = sx(point.x), y = sy(point.y);
          if (!started) { ctx.moveTo(x, y); started = true; } else ctx.lineTo(x, y);
        }
        if (started) ctx.stroke();
      }
    }
    ctx.restore();
  }

  ctx.fillStyle = "#7e879b";
  ctx.textAlign = "right";
  ctx.textBaseline = "alphabetic";
  if (scene.xlabel) ctx.fillText(String(scene.xlabel), margin.left + plotW, height - 7);
  if (scene.ylabel) {
    ctx.save(); ctx.translate(16, margin.top + plotH / 2); ctx.rotate(-Math.PI / 2);
    ctx.textAlign = "center"; ctx.fillText(String(scene.ylabel), 0, 0); ctx.restore();
  }
  ctx.restore();
}

// The polar frame keeps room for theta labels outside the circle, and for the
// colourbar column when the scene has one.  Mirrors Plot.polar_layout.
function polarLayout(width, height, hasColorbar) {
  return frameLayout(52, 34, width - 52, height - 30, hasColorbar);
}

// Trace one annular cell part in Canvas coordinates.  World angles are y-down,
// so Canvas angles are negated; the outer arc runs start -> end and the inner
// arc runs back end -> start.
function tracePolarCell(ctx, cx, cy, cell, part) {
  const start = part.startAngle;
  const end = part.endAngle;
  const outer = cell.outerRadius;
  const inner = cell.innerRadius;
  if (inner <= 0.0005) {
    ctx.moveTo(cx, cy);
    ctx.arc(cx, cy, outer, -start, -end, end > start);
    ctx.closePath();
    return;
  }
  ctx.moveTo(cx + outer * Math.cos(start), cy - outer * Math.sin(start));
  ctx.arc(cx, cy, outer, -start, -end, end > start);
  ctx.lineTo(cx + inner * Math.cos(end), cy - inner * Math.sin(end));
  ctx.arc(cx, cy, inner, -end, -start, end < start);
  ctx.closePath();
}

function drawPolarFields(ctx, cx, cy, radius, resolved) {
  for (const heatmap of resolved.heatmaps) {
    for (const cell of heatmapCells(heatmap, cx, cy, radius, resolved.rmax,
      resolved.thetaZero, resolved.direction)) {
      ctx.save();
      ctx.globalAlpha = Math.max(0, Math.min(1, cell.alpha));
      ctx.fillStyle = cell.color;
      if (cell.fullDisc) {
        ctx.beginPath();
        ctx.arc(cx, cy, cell.outerRadius, 0, TAU);
        ctx.fill();
      } else {
        for (const part of cell.parts) {
          ctx.beginPath();
          tracePolarCell(ctx, cx, cy, cell, part);
          ctx.fill();
        }
      }
      ctx.restore();
    }
  }

  for (const contour of resolved.contours) {
    ctx.save();
    ctx.globalAlpha = Math.max(0, Math.min(1, contour.style.alpha));
    ctx.strokeStyle = contour.style.color;
    ctx.fillStyle = contour.style.color;
    ctx.lineWidth = Math.max(0.1, contour.style.linewidth);
    if (contour.style.linestyle === "dashed") ctx.setLineDash([6, 4]);
    else if (contour.style.linestyle === "dotted") ctx.setLineDash([1.5, 3]);
    else ctx.setLineDash([]);
    for (const level of contour.levels) {
      for (const segment of level.segments) {
        const points = contourSegmentPoints(contour, segment, cx, cy, radius,
          resolved.rmax, resolved.thetaZero, resolved.direction);
        if (!points.length) continue;
        ctx.beginPath();
        ctx.moveTo(points[0].x, points[0].y);
        for (let index = 1; index < points.length; index += 1) {
          ctx.lineTo(points[index].x, points[index].y);
        }
        ctx.stroke();
      }
    }
    ctx.setLineDash([]);
    for (const level of contour.levels) {
      const label = contourLabel(contour, level, cx, cy, radius, resolved.rmax,
        resolved.thetaZero, resolved.direction);
      if (label === null) continue;
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(label.text, label.x, label.y);
    }
    ctx.restore();
  }
}

function drawPolarColorbar(ctx, colorbar, cx, cy, radius) {
  const { x, y, width, height } = colorbarLayout(cx, cy, radius);
  for (const step of colorbarSteps(colorbar)) {
    const top = y + height * step.y0;
    const bottom = y + height * step.y1;
    ctx.fillStyle = step.color;
    ctx.fillRect(x, top, width, Math.max(1, bottom - top));
  }

  ctx.strokeStyle = "#42506a";
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(x, y); ctx.lineTo(x + width, y);
  ctx.lineTo(x + width, y + height); ctx.lineTo(x, y + height);
  ctx.closePath();
  ctx.stroke();

  ctx.fillStyle = "#7e879b";
  ctx.font = "10px ui-sans-serif, system-ui, sans-serif";
  ctx.textAlign = "left";
  ctx.textBaseline = "middle";
  let maxLabel = 0;
  for (const tick of colorbarTicks(colorbar)) {
    const tickY = y + height * (1 - tick.fraction);
    ctx.beginPath();
    ctx.moveTo(x + width, tickY); ctx.lineTo(x + width + 4, tickY);
    ctx.stroke();
    if (tick.label !== null) {
      ctx.fillText(tick.label, x + width + 8, tickY + 3.5);
      maxLabel = Math.max(maxLabel, tick.label.length * 5.5);
    }
  }
  if (colorbar.label !== null) {
    const titleX = x + width + 8 + maxLabel + 14;
    ctx.save();
    ctx.translate(titleX, y + height / 2);
    ctx.rotate(-Math.PI / 2);
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(colorbar.label, 0, 0);
    ctx.restore();
  }
  ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
}

function drawPolar(canvas, scene, ctx) {
  const { width, height } = cssSize(canvas);
  const resolved = resolvePolar(scene);
  const polar = resolved.polar;
  const rmax = resolved.rmax;
  const thetaZero = resolved.thetaZero;
  const direction = resolved.direction;
  const { cx, cy, radius } = polarLayout(width, height,
    resolved.colorbar !== null);

  ctx.save();
  ctx.fillStyle = "#0c1019";
  ctx.fillRect(0, 0, width, height);
  ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
  ctx.textBaseline = "middle";

  if (scene.grid !== false) {
    const rings = polarRings(polar, rmax);
    const spokes = polarSpokes(polar);
    ctx.strokeStyle = "#1d2433";
    ctx.lineWidth = 1;
    for (const tick of rings) {
      const ringRadius = radius * tick.value / rmax;
      ctx.beginPath(); ctx.arc(cx, cy, ringRadius, 0, TAU); ctx.stroke();
    }
    for (const tick of spokes) {
      const angle = thetaZero + direction * tick.value;
      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(cx + radius * Math.cos(angle), cy - radius * Math.sin(angle));
      ctx.stroke();
    }
  }

  drawPolarFields(ctx, cx, cy, radius, resolved);

  if (scene.grid !== false) {
    const rings = polarRings(polar, rmax);
    const spokes = polarSpokes(polar);
    ctx.fillStyle = "#7e879b";
    ctx.font = "10px ui-sans-serif, system-ui, sans-serif";
    for (const tick of rings) {
      const label = radiusLabel(tick);
      if (label === null) continue;
      const ringRadius = radius * tick.value / rmax;
      const position = ringLabelPosition(cx, cy, ringRadius);
      ctx.textAlign = "right";
      ctx.fillText(label, position.x, position.y);
    }
    for (const tick of spokes) {
      const label = thetaLabel(tick);
      if (label === null) continue;
      const angle = thetaZero + direction * tick.value;
      const position = thetaLabelPosition(cx, cy, radius, angle);
      ctx.textAlign = "center";
      ctx.fillText(label, position.x, position.y);
    }
    ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
  }

  ctx.strokeStyle = "#42506a";
  ctx.lineWidth = 1.2;
  ctx.beginPath(); ctx.arc(cx, cy, radius, 0, TAU); ctx.stroke();

  for (const series of resolved.series) {
    ctx.save();
    ctx.globalAlpha = Math.max(0, Math.min(1, series.alpha));
    if (series.points) {
      if (series.kind === "line") {
        ctx.strokeStyle = series.color;
        ctx.lineWidth = 1.8;
        const step = sampleStep(series.points.length, LINE_SAMPLE_LIMIT);
        ctx.beginPath();
        let started = false;
        for (let index = 0; index < series.points.length; index += step) {
          const point = series.points[index];
          const projected = projectPolar(cx, cy, radius, rmax, thetaZero,
            direction, point.theta, point.r);
          if (!started) { ctx.moveTo(projected.x, projected.y); started = true; }
          else ctx.lineTo(projected.x, projected.y);
        }
        if (started) ctx.stroke();
      } else {
        const step = sampleStep(series.points.length, SCATTER_SAMPLE_LIMIT);
        for (let index = 0; index < series.points.length; index += step) {
          const point = series.points[index];
          const projected = projectPolar(cx, cy, radius, rmax, thetaZero,
            direction, point.theta, point.r);
          ctx.fillStyle = point.color || series.color;
          ctx.beginPath();
          ctx.arc(projected.x, projected.y, pointRadius(point), 0, TAU);
          ctx.fill();
        }
      }
    } else if (series.bars) {
      const step = sampleStep(series.bars.length, BAR_SAMPLE_LIMIT);
      for (let index = 0; index < series.bars.length; index += step) {
        const bar = series.bars[index];
        for (const sector of barSectors(bar, radius, rmax, thetaZero, direction)) {
          ctx.fillStyle = sector.color || series.color;
          ctx.beginPath();
          if (sector.full) {
            ctx.arc(cx, cy, sector.radius, 0, TAU);
          } else {
            ctx.moveTo(cx, cy);
            const anticlockwise = sector.endAngle > sector.startAngle;
            ctx.arc(cx, cy, sector.radius, -sector.startAngle,
              -sector.endAngle, anticlockwise);
          }
          ctx.closePath();
          ctx.fill();
        }
      }
    } else if (series.arrows) {
      const arrows = quiverArrows(series, cx, cy, radius, rmax, thetaZero,
        direction);
      if (arrows.length) {
        // luaplotlib clips arrow glyphs to the polar circle; Canvas gets the
        // same boundary without clipping the other series.
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, TAU);
        ctx.clip();
      }
      ctx.strokeStyle = series.color;
      ctx.fillStyle = series.color;
      ctx.lineWidth = Math.max(0.1, series.linewidth);
      for (const arrow of arrows) {
        if (arrow.shaft) {
          ctx.beginPath();
          ctx.moveTo(arrow.tailX, arrow.tailY);
          ctx.lineTo(arrow.neckX, arrow.neckY);
          ctx.stroke();
        }
        if (arrow.headed) {
          ctx.beginPath();
          ctx.moveTo(arrow.headX1, arrow.headY1);
          ctx.lineTo(arrow.headX2, arrow.headY2);
          ctx.lineTo(arrow.headX3, arrow.headY3);
          ctx.closePath();
          ctx.fill();
        }
      }
    }
    ctx.restore();
  }

  if (resolved.colorbar !== null) {
    drawPolarColorbar(ctx, resolved.colorbar, cx, cy, radius);
  }

  ctx.fillStyle = "#dfe5f4";
  ctx.font = "600 13px ui-sans-serif, system-ui, sans-serif";
  ctx.textAlign = "left";
  ctx.textBaseline = "top";
  if (scene.title) ctx.fillText(String(scene.title), 12, 12);

  ctx.fillStyle = "#7e879b";
  ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
  if (scene.xlabel) {
    ctx.textAlign = "center";
    ctx.textBaseline = "alphabetic";
    ctx.fillText(String(scene.xlabel), cx, height - 8);
  }
  if (scene.ylabel) {
    ctx.save();
    ctx.translate(14, cy);
    ctx.rotate(-Math.PI / 2);
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(String(scene.ylabel), 0, 0);
    ctx.restore();
  }
  ctx.restore();
}

function formatTick(value) {
  if (!Number.isFinite(value)) return "";
  if (Math.abs(value) >= 10000 || (Math.abs(value) > 0 && Math.abs(value) < 0.01)) return value.toExponential(1);
  return Number(value.toFixed(2)).toString();
}

function drawCube(canvas, ctx) {
  const { width, height } = cssSize(canvas);
  ctx.fillStyle = "#0c1019"; ctx.fillRect(0, 0, width, height);
  const cx = width / 2, cy = height / 2 + 4;
  const scale = Math.min(width, height) * 0.25;
  const ax = 0.62, ay = 0.75;
  const project = (x, y, z) => {
    const ry = x * Math.cos(ay) - z * Math.sin(ay);
    const rz = x * Math.sin(ay) + z * Math.cos(ay);
    const rx = y * Math.cos(ax) - rz * Math.sin(ax);
    const depth = y * Math.sin(ax) + rz * Math.cos(ax);
    const p = 1 / (2.6 - depth * 0.35);
    return [cx + ry * scale * p, cy - rx * scale * p];
  };
  const vertices = [];
  for (const x of [-1, 1]) for (const y of [-1, 1]) for (const z of [-1, 1]) vertices.push(project(x, y, z));
  const edges = [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]];
  ctx.strokeStyle = "#8aa4ff"; ctx.lineWidth = 1.5; ctx.globalAlpha = 0.85;
  for (const [a, b] of edges) {
    ctx.beginPath(); ctx.moveTo(vertices[a][0], vertices[a][1]); ctx.lineTo(vertices[b][0], vertices[b][1]); ctx.stroke();
  }
  ctx.globalAlpha = 0.22;
  for (const v of vertices) { ctx.beginPath(); ctx.arc(v[0], v[1], 3, 0, Math.PI * 2); ctx.fill(); }
  ctx.globalAlpha = 1;
  ctx.fillStyle = "#7e879b"; ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
  ctx.textAlign = "center"; ctx.fillText("cube · scene string rendered in the browser", width / 2, height - 12);
}

function drawGrid(canvas, ctx) {
  const { width, height } = cssSize(canvas);
  ctx.fillStyle = "#0c1019"; ctx.fillRect(0, 0, width, height);
  const cx = width / 2, cy = height * 0.66;
  const scale = Math.min(width, height) * 0.28;
  ctx.strokeStyle = "#35415a"; ctx.lineWidth = 1;
  for (let i = -6; i <= 6; i += 1) {
    const t = i / 6;
    ctx.beginPath();
    ctx.moveTo(cx - scale, cy + t * scale * 0.44 - scale * 0.2);
    ctx.lineTo(cx + scale, cy + t * scale * 0.44 - scale * 0.2);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(cx + t * scale, cy - scale * 0.34);
    ctx.lineTo(cx + t * scale, cy + scale * 0.34);
    ctx.stroke();
  }
  ctx.strokeStyle = "#8aa4ff"; ctx.globalAlpha = 0.8;
  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx, cy - scale * 0.62); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + scale * 0.58, cy + scale * 0.2); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx - scale * 0.58, cy + scale * 0.2); ctx.stroke();
  ctx.globalAlpha = 1;
  ctx.fillStyle = "#7e879b"; ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
  ctx.textAlign = "center"; ctx.fillText("grid · scene string rendered in the browser", width / 2, height - 12);
}

function drawPlaceholder(canvas, ctx, scene) {
  const { width, height } = cssSize(canvas);
  ctx.fillStyle = "#0c1019"; ctx.fillRect(0, 0, width, height);
  ctx.fillStyle = "#7e879b"; ctx.font = "12px ui-sans-serif, system-ui, sans-serif"; ctx.textAlign = "center";
  const label = typeof scene === "string" ? `${scene} scene` : "scene output";
  ctx.fillText(label, width / 2, height / 2 - 4);
  ctx.fillStyle = "#4f586d"; ctx.font = "11px ui-sans-serif, system-ui, sans-serif";
  ctx.fillText("renderer not available for this scene type", width / 2, height / 2 + 16);
}

// Paint any scene into a canvas.  Kept separate from renderScene so the
// headless scene QA can draw deterministic canvases without the DOM shell.
export function paintScene(canvas, scene) {
  const ctx = canvas.getContext("2d");
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.min((typeof window !== "undefined" && window.devicePixelRatio) || 1, 2);
  canvas.width = Math.max(1, Math.round(rect.width * dpr));
  canvas.height = Math.max(1, Math.round(rect.height * dpr));
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const { width, height } = cssSize(canvas);
  ctx.clearRect(0, 0, width, height);
  if (scene === "cube") return drawCube(canvas, ctx);
  if (scene === "grid") return drawGrid(canvas, ctx);
  if (scene && typeof scene === "object") {
    const polar = scene.orientation === "polar";
    if (polar) return drawPolar(canvas, scene, ctx);
    if (scene.type === "luaplotlib" || Array.isArray(scene.series)) {
      return drawChart(canvas, scene, ctx);
    }
  }
  return drawPlaceholder(canvas, ctx, scene);
}

export function drawScene(canvas) {
  const scene = scenes.get(canvas);
  if (scene === undefined) return;
  paintScene(canvas, scene);
}

export function renderScene(container, scene) {
  container.replaceChildren();
  if (scene == null) return;
  const wrap = document.createElement("div");
  wrap.className = "scene-wrap";
  const canvas = document.createElement("canvas");
  canvas.className = "scene-canvas";
  const polar = typeof scene === "object" && scene.orientation === "polar";
  canvas.setAttribute("aria-label", polar ? "Polar scene output" : "Scene output");
  scenes.set(canvas, scene);
  wrap.appendChild(canvas);
  const caption = document.createElement("div");
  caption.className = "scene-caption";
  const type = typeof scene === "string" ? scene : scene.type || "scene";
  const kind = polar ? "luaplotlib polar"
    : typeof scene === "object" ? "luaplotlib" : "LÖVR scene";
  caption.innerHTML = `<span>${escapeText(type)} · rendered locally</span><span>${kind}</span>`;
  wrap.appendChild(caption);
  container.appendChild(wrap);
  requestAnimationFrame(() => drawScene(canvas));
  if (typeof ResizeObserver !== "undefined") {
    const observer = new ResizeObserver(() => drawScene(canvas));
    observer.observe(wrap);
    canvas._sceneObserver = observer;
  }
}

function escapeText(value) {
  return String(value).replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
}

export function redrawScenes(root = document) {
  root.querySelectorAll(".scene-canvas").forEach((canvas) => drawScene(canvas));
}
