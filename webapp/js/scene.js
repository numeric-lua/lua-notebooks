const PALETTE = ["#8aa4ff", "#ff9f6e", "#62d7a2", "#f6c177", "#d59bff", "#6ecbff"];
const scenes = new WeakMap();

function cssSize(canvas) {
  const rect = canvas.getBoundingClientRect();
  return { width: Math.max(240, rect.width || 600), height: Math.max(120, rect.height || 230) };
}

function number(value, fallback) {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function valuesOf(series, key) {
  return Array.isArray(series[key]) ? series[key].filter((v) => Number.isFinite(Number(v))).map(Number) : [];
}

function bounds(scene) {
  let xmin = Infinity, xmax = -Infinity, ymin = Infinity, ymax = -Infinity;
  for (const series of scene.series || []) {
    const xs = valuesOf(series, "x");
    const ys = valuesOf(series, "y");
    for (let i = 0; i < Math.min(xs.length, ys.length); i += 1) {
      xmin = Math.min(xmin, xs[i]); xmax = Math.max(xmax, xs[i]);
      ymin = Math.min(ymin, ys[i]); ymax = Math.max(ymax, ys[i]);
    }
  }
  if (!Number.isFinite(xmin)) { xmin = 0; xmax = 1; ymin = 0; ymax = 1; }
  if (xmax === xmin) { xmax += 1; xmin -= 1; }
  if (ymax === ymin) { ymax += 1; ymin -= 1; }
  xmin = number(scene.xlim?.[0], xmin); xmax = number(scene.xlim?.[1], xmax);
  ymin = number(scene.ylim?.[0], ymin); ymax = number(scene.ylim?.[1], ymax);
  const xpad = (xmax - xmin) * 0.04 || 0.1;
  const ypad = (ymax - ymin) * 0.08 || 0.1;
  return { xmin: xmin - xpad, xmax: xmax + xpad, ymin: ymin - ypad, ymax: ymax + ypad };
}

function drawChart(canvas, scene, ctx) {
  const { width, height } = cssSize(canvas);
  const margin = { left: 44, right: 16, top: scene.title ? 32 : 16, bottom: 34 };
  const plotW = width - margin.left - margin.right;
  const plotH = height - margin.top - margin.bottom;
  const b = bounds(scene);
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
  for (let i = 0; i <= 4; i += 1) {
    const value = b.xmin + ((b.xmax - b.xmin) * i) / 4;
    const x = sx(value);
    ctx.fillText(formatTick(value), x, margin.top + plotH + 16);
  }

  const clipBottom = Math.max(b.ymin, Math.min(0, b.ymax));
  scene.series?.forEach((series, index) => {
    const color = series.style?.color || PALETTE[index % PALETTE.length];
    const alpha = series.style?.alpha ?? 1;
    const xs = valuesOf(series, "x");
    const ys = valuesOf(series, "y");
    const count = Math.min(xs.length, ys.length);
    if (!count) return;
    ctx.save();
    ctx.globalAlpha = Math.max(0, Math.min(1, alpha));
    ctx.strokeStyle = color;
    ctx.fillStyle = color;
    if (series.kind === "bar") {
      const zero = sy(clipBottom);
      let width = Math.max(2, plotW / Math.max(1, count) * 0.66);
      if (count > 1) {
        const gap = Math.abs(sx(xs[1]) - sx(xs[0]));
        width = Math.max(2, gap * 0.68);
      }
      for (let i = 0; i < count; i += 1) {
        const x = sx(xs[i]) - width / 2;
        const y = sy(ys[i]);
        ctx.fillRect(x, Math.min(y, zero), width, Math.abs(zero - y));
      }
    } else if (series.kind === "scatter") {
      const radius = Math.max(1.5, Number(series.style?.radius) || 3);
      for (let i = 0; i < count; i += 1) {
        ctx.beginPath(); ctx.arc(sx(xs[i]), sy(ys[i]), radius, 0, Math.PI * 2); ctx.fill();
      }
    } else {
      ctx.lineWidth = Number(series.style?.width) || 1.6;
      ctx.beginPath();
      for (let i = 0; i < count; i += 1) {
        const x = sx(xs[i]), y = sy(ys[i]);
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }
    ctx.restore();
  });

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

export function drawScene(canvas) {
  const scene = scenes.get(canvas);
  if (scene === undefined) return;
  const ctx = canvas.getContext("2d");
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.max(1, Math.round(rect.width * dpr));
  canvas.height = Math.max(1, Math.round(rect.height * dpr));
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const { width, height } = cssSize(canvas);
  ctx.clearRect(0, 0, width, height);
  if (scene === "cube") return drawCube(canvas, ctx);
  if (scene === "grid") return drawGrid(canvas, ctx);
  if (scene && typeof scene === "object" && scene.type === "luaplotlib") return drawChart(canvas, scene, ctx);
  return drawPlaceholder(canvas, ctx, scene);
}

export function renderScene(container, scene) {
  container.replaceChildren();
  if (scene == null) return;
  const wrap = document.createElement("div");
  wrap.className = "scene-wrap";
  const canvas = document.createElement("canvas");
  canvas.className = "scene-canvas";
  canvas.setAttribute("aria-label", "Scene output");
  scenes.set(canvas, scene);
  wrap.appendChild(canvas);
  const caption = document.createElement("div");
  caption.className = "scene-caption";
  const type = typeof scene === "string" ? scene : scene.type || "scene";
  caption.innerHTML = `<span>${escapeText(type)} · rendered locally</span><span>${typeof scene === "object" ? "luaplotlib" : "LÖVR scene"}</span>`;
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
