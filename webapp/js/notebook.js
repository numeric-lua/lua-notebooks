const STORAGE_KEY = "lua-notebooks-web:v1";
const URL_KEY = "lua-notebooks-web:url";

function randomId(prefix) {
  if (globalThis.crypto?.randomUUID) return `${prefix}-${crypto.randomUUID().slice(0, 8)}`;
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
}

export function createCell(kind = "code", source = "") {
  return { id: randomId("cell"), kind, source };
}

export function createNotebook(name = "Untitled.luanb", cells = null) {
  return {
    id: randomId("nb"),
    name,
    cells: cells?.length ? cells : [createCell("code", "")],
    updatedAt: Date.now(),
  };
}

function welcomeNotebook() {
  return createNotebook("welcome.luanb", [
    createCell("markdown", `# Lua Notebooks · Web

A browser front-end for a **remote LuaJIT kernel**. The editor and 3D/2D outputs run here; the kernel runs on the machine with your Lua libraries.

- **Shift+Enter** runs the focused cell.
- Code cells return values and captured output.
- Markdown, widgets, charts, and scene strings are rendered locally.

The gateway is a WebSocket server — no Emscripten, threads, or COOP/COEP headers are required.`),
    createCell("code", `print("hello from the browser")
print("the kernel is LuaJIT on the other side")
return 6 * 7`),
    createCell("markdown", `## Math and markdown

Inline math: $E = mc^2$. A formula:

$$\\int_0^1 x^2 \\, dx = \\frac{1}{3}$$

> Notebooks are documents first. The window is just a view.`),
    createCell("code", `local xs, ys = {}, {}
for i = 1, 80 do
  local x = (i - 1) * 0.1
  xs[i] = x
  ys[i] = math.sin(x)
end
return { scene = {
  type = "luaplotlib", title = "sin(x)", xlabel = "x", ylabel = "y",
  xlim = { 0, 8 }, ylim = { -1.2, 1.2 }, grid = true,
  series = {
    { kind = "line", x = xs, y = ys,
      style = { color = "#8aa4ff", width = 2, label = "sin" } },
    { kind = "scatter", x = { 0, math.pi / 2, math.pi },
      y = { 0, 1, 0 },
      style = { color = "#ff9f6e", radius = 4, label = "samples" } },
  },
} }`),
    createCell("code", `local theta, r = {}, {}
for i = 1, 96 do
  local a = (i - 1) * 2 * math.pi / 96
  theta[i] = a
  r[i] = 1 + 0.8 * math.sin(4 * a)
end
return { scene = {
  type = "luaplotlib", orientation = "polar", title = "polar rose",
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" },
      { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 0.5, label = "0.5" }, { value = 1, label = "1" },
      { value = 1.5, label = "1.5" }, { value = 2, label = "2" },
    },
    series = {
      { kind = "line", theta = theta, r = r,
        style = { color = "#8aa4ff", label = "rose" } },
      { kind = "bar", theta = { math.pi / 4 }, r = { 1.5 },
        widths = { 0.45 }, colors = { "#62d7a2" } },
    },
  },
} }`),
    createCell("code", `-- Polar heatmap, contour, and colorbar.
local rows, cols = 5, 8
local values = {}
for row = 1, rows do
  values[row] = {}
  for col = 1, cols do
    local radius = (row - 1) / (rows - 1)
    local angle = (col - 1) * 2 * math.pi / cols
    values[row][col] = 0.5 + 0.5 * math.sin(3 * angle) * radius
  end
end
return { scene = {
  type = "luaplotlib", orientation = "polar", title = "polar heatmap",
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 0.5, label = "0.5" }, { value = 1, label = "1" },
      { value = 1.5, label = "1.5" }, { value = 2, label = "2" },
    },
    heatmaps = { {
      rows = rows, cols = cols, values = values,
      vmin = 0, vmax = 1, rmin = 0, rmax = 2,
      theta_min = 0, theta_max = 2 * math.pi,
      alpha = 1, label = "density", colorbar = true,
    } },
    contours = { {
      rows = rows, cols = cols,
      levels = {
        { level = 0.25, segments = {
          { 0, 0.8, 1.2, 1.2 }, { 2.4, 0.8, 3.8, 1.2 } } },
        { level = 0.75, segments = {
          { 0.4, 1.2, 1.6, 1.6 }, { 2.8, 1.0, 4.2, 1.4 } } },
      },
      labels = true,
      style = { color = "#ffd166", linewidth = 1.5, alpha = 0.95,
        linestyle = "dashed", label = "isolines" },
    } },
    colorbar = { orientation = "vertical", vmin = 0, vmax = 1,
      ticks = { 0, 0.5, 1 }, label = "density" },
  },
} }`),
    createCell("code", `widgets.slider({ label = "gain", min = 0, max = 10, value = 3,
  on_change = function(value) print("gain", value) end })
widgets.button({ label = "Ping",
  on_click = function() print("pong") end })
widgets.checkbox({ label = "enabled", value = true })`),
    createCell("code", `-- Scene strings work too: cube, grid.
return { scene = "cube" }`),
    createCell("code", `-- Large polar heatmaps are sampled into blocks before painting.
local rows, cols = 96, 96
local values = {}
for row = 1, rows do
  values[row] = {}
  for col = 1, cols do
    local radius = (row - 1) / (rows - 1)
    local angle = (col - 1) * 2 * math.pi / cols
    values[row][col] = 0.5 + 0.5 * math.sin(3 * angle) * radius
  end
end
return { scene = {
  type = "luaplotlib", orientation = "polar", title = "large polar heatmap",
  polar = {
    theta_zero = 0, theta_direction = "counterclockwise", rmax = 2,
    theta_ticks = {
      { value = 0, label = "0" }, { value = math.pi / 2, label = "90" },
      { value = math.pi, label = "180" },
      { value = 3 * math.pi / 2, label = "270" },
    },
    r_ticks = {
      { value = 0.5, label = "0.5" }, { value = 1, label = "1" },
      { value = 1.5, label = "1.5" }, { value = 2, label = "2" },
    },
    heatmaps = { {
      rows = rows, cols = cols, values = values,
      vmin = 0, vmax = 1, rmin = 0, rmax = 2,
      theta_min = 0, theta_max = 2 * math.pi,
      alpha = 1, label = "density", colorbar = true,
    } },
    colorbar = { orientation = "vertical", vmin = 0, vmax = 1,
      ticks = { 0, 0.5, 1 }, label = "density" },
  },
} }`),
  ]);
}

export function loadState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return defaultState();
    const data = JSON.parse(raw);
    if (!Array.isArray(data.notebooks) || !data.notebooks.length) return defaultState();
    const notebooks = data.notebooks.map(normalizeNotebook).filter(Boolean);
    if (!notebooks.length) return defaultState();
    let activeId = data.activeId;
    if (!notebooks.some((notebook) => notebook.id === activeId)) activeId = notebooks[0].id;
    return { notebooks, activeId };
  } catch {
    return defaultState();
  }
}

function defaultState() {
  const notebook = welcomeNotebook();
  return { notebooks: [notebook], activeId: notebook.id };
}

function normalizeNotebook(value) {
  if (!value || typeof value !== "object") return null;
  const cells = Array.isArray(value.cells)
    ? value.cells.filter((cell) => cell && (cell.kind === "code" || cell.kind === "markdown"))
      .map((cell) => ({
        id: typeof cell.id === "string" && cell.id ? cell.id : randomId("cell"),
        kind: cell.kind,
        source: typeof cell.source === "string" ? cell.source : "",
      }))
    : [];
  if (!cells.length) cells.push(createCell("code", ""));
  return {
    id: typeof value.id === "string" && value.id ? value.id : randomId("nb"),
    name: typeof value.name === "string" && value.name ? value.name : "Untitled.luanb",
    cells,
    updatedAt: Number(value.updatedAt) || Date.now(),
  };
}

export function saveState(state) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      activeId: state.activeId,
      notebooks: state.notebooks.map((notebook) => ({
        id: notebook.id,
        name: notebook.name,
        updatedAt: notebook.updatedAt,
        cells: notebook.cells.map((cell) => ({
          id: cell.id, kind: cell.kind, source: cell.source,
        })),
      })),
    }));
    return true;
  } catch {
    return false;
  }
}

export function loadGatewayUrl() {
  const query = new URLSearchParams(location.search).get("ws");
  if (query) return query;
  return localStorage.getItem(URL_KEY) || "ws://127.0.0.1:8765";
}

export function saveGatewayUrl(url) {
  try { localStorage.setItem(URL_KEY, url); } catch { /* ignore */ }
}

export function exportNotebook(notebook) {
  return JSON.stringify({
    version: 1,
    name: notebook.name,
    cells: notebook.cells.map((cell) => ({
      id: cell.id, kind: cell.kind, source: cell.source,
    })),
  }, null, 2);
}

export function importNotebook(text) {
  const data = JSON.parse(text);
  if (!data || data.version !== 1 || typeof data.name !== "string" || !Array.isArray(data.cells)) {
    throw new Error("Not a lua-notebooks v1 file");
  }
  const cells = data.cells.map((cell) => {
    if (!cell || (cell.kind !== "code" && cell.kind !== "markdown")) {
      throw new Error("Invalid cell in notebook");
    }
    return createCell(cell.kind, typeof cell.source === "string" ? cell.source : "");
  });
  if (!cells.length) throw new Error("Notebook has no cells");
  return createNotebook(data.name.endsWith(".luanb") ? data.name : `${data.name}.luanb`, cells);
}

export function uniqueNotebookName(state, base = "Untitled.luanb") {
  const names = new Set(state.notebooks.map((notebook) => notebook.name));
  if (!names.has(base)) return base;
  const stem = base.replace(/\.luanb$/, "");
  let index = 2;
  while (names.has(`${stem}-${index}.luanb`)) index += 1;
  return `${stem}-${index}.luanb`;
}
