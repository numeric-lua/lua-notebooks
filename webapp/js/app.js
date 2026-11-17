import { Gateway } from "./gateway.js";
import {
  createCell, createNotebook, exportNotebook, importNotebook, loadGatewayUrl,
  loadState, saveGatewayUrl, saveState, uniqueNotebookName,
} from "./notebook.js";
import { renderMarkdown } from "./markdown.js";
import { redrawScenes, renderScene } from "./scene.js";

const dom = {
  sidebar: document.getElementById("sidebar"),
  sidebarToggle: document.getElementById("sidebar-toggle"),
  notebookList: document.getElementById("notebook-list"),
  title: document.getElementById("notebook-title"),
  heading: document.getElementById("notebook-heading"),
  cells: document.getElementById("cells"),
  addCode: document.querySelector('[data-add="code"]'),
  addMarkdown: document.querySelector('[data-add="markdown"]'),
  newNotebook: document.getElementById("new-notebook"),
  deleteNotebook: document.getElementById("delete-notebook"),
  importNotebook: document.getElementById("import-notebook"),
  exportNotebook: document.getElementById("export-notebook"),
  fileInput: document.getElementById("file-input"),
  restart: document.getElementById("restart-kernel"),
  runAll: document.getElementById("run-all"),
  settings: document.getElementById("settings-button"),
  settingsDialog: document.getElementById("settings-dialog"),
  settingsForm: document.getElementById("settings-form"),
  wsUrl: document.getElementById("ws-url"),
  connect: document.getElementById("connect-button"),
  connection: document.getElementById("connection"),
  statusDot: document.getElementById("status-dot"),
  statusLabel: document.getElementById("status-label"),
  runtime: document.getElementById("kernel-runtime"),
  cellCount: document.getElementById("cell-count"),
  saveStatus: document.getElementById("save-status"),
  toast: document.getElementById("toast"),
};

const state = loadState();
let active = state.notebooks.find((notebook) => notebook.id === state.activeId) || state.notebooks[0];
let wsUrl = loadGatewayUrl();
let gateway;
let reconnectTimer = null;
let saveTimer = null;
let toastTimer = null;
let hello = false;
let connected = false;
let ready = new Set();
let opening = new Set();
let pending = new Map();
let queue = [];

function notebook() {
  return state.notebooks.find((item) => item.id === active.id) || active;
}

function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    const ok = saveState(state);
    dom.saveStatus.textContent = ok ? "saved locally" : "could not save";
    dom.saveStatus.style.color = ok ? "" : "var(--red)";
  }, 180);
}

function toast(message, isError = false) {
  clearTimeout(toastTimer);
  dom.toast.textContent = message;
  dom.toast.classList.toggle("error", isError);
  dom.toast.classList.add("visible");
  toastTimer = setTimeout(() => dom.toast.classList.remove("visible"), 3200);
}

function setConnection(status, label) {
  dom.connection.classList.remove("connecting", "ready", "error");
  if (status) dom.connection.classList.add(status);
  dom.statusLabel.textContent = label;
  dom.runAll.disabled = !(connected && ready.has(active.id));
  refreshRunButtons();
}

function refreshRunButtons() {
  const disabled = !(connected && ready.has(active.id));
  document.querySelectorAll(".run-button").forEach((button) => {
    if (!button.closest(".cell")?.classList.contains("running")) button.disabled = disabled;
  });
}

function statusReady() {
  return connected && ready.has(active.id);
}

function cellById(id) {
  return notebook().cells.find((cell) => cell.id === id);
}

function cellElement(id) {
  return dom.cells.querySelector(`.cell[data-id="${CSS.escape(id)}"]`);
}

function updateLines(textarea, lines) {
  const count = Math.max(1, textarea.value.split("\n").length);
  lines.replaceChildren();
  for (let i = 1; i <= count; i += 1) {
    const span = document.createElement("span");
    span.textContent = String(i);
    lines.appendChild(span);
  }
  textarea.style.height = "auto";
  textarea.style.height = `${Math.max(52, textarea.scrollHeight)}px`;
}

function renderAll() {
  active = notebook();
  dom.title.value = active.name;
  dom.heading.textContent = active.name.replace(/\.luanb$/, "");
  dom.cellCount.textContent = String(active.cells.length);
  dom.cells.replaceChildren();
  active.cells.forEach((cell, index) => renderCell(cell, index));
  renderSidebar();
  refreshRunButtons();
  if (connected && hello && !ready.has(active.id)) openKernel(active.id);
}

function renderSidebar() {
  dom.notebookList.replaceChildren();
  for (const item of state.notebooks) {
    const button = document.createElement("button");
    button.className = `notebook-item${item.id === active.id ? " active" : ""}`;
    button.type = "button";
    const icon = document.createElement("span");
    icon.className = "nb-icon";
    icon.textContent = "◈";
    const name = document.createElement("span");
    name.className = "nb-name";
    name.textContent = item.name.replace(/\.luanb$/, "");
    button.append(icon, name);
    button.addEventListener("click", () => switchNotebook(item.id));
    dom.notebookList.appendChild(button);
  }
}

function switchNotebook(id) {
  if (id === active.id) {
    dom.sidebar.classList.remove("open");
    return;
  }
  if (!state.notebooks.some((item) => item.id === id)) return;
  active = state.notebooks.find((item) => item.id === id);
  state.activeId = active.id;
  save();
  renderAll();
  if (connected && hello && !ready.has(active.id)) openKernel(active.id);
  dom.sidebar.classList.remove("open");
}

function renderCell(cell, index) {
  const section = document.createElement("section");
  section.className = "cell";
  section.dataset.id = cell.id;
  if (cell.running) section.classList.add("running");

  const gutter = document.createElement("div");
  gutter.className = "cell-gutter";
  const number = document.createElement("span");
  number.className = "cell-index";
  number.textContent = String(index + 1);
  const run = document.createElement("button");
  run.className = "run-button";
  run.type = "button";
  run.title = "Run cell (Shift+Enter)";
  run.textContent = "▶";
  run.disabled = !statusReady();
  if (cell.kind !== "code") {
    run.style.visibility = "hidden";
    run.tabIndex = -1;
  }
  run.addEventListener("click", () => runCell(cell.id));
  gutter.append(number, run);

  const body = document.createElement("div");
  body.className = "cell-body";
  const head = document.createElement("div");
  head.className = "cell-head";
  const kind = document.createElement("select");
  kind.className = "kind-select";
  kind.innerHTML = '<option value="code">CODE</option><option value="markdown">MARKDOWN</option>';
  kind.value = cell.kind;
  kind.addEventListener("change", () => {
    cell.kind = kind.value;
    cell.output = "";
    cell.value = "";
    cell.error = null;
    cell.scene = null;
    cell.widgets = [];
    save();
    renderAll();
  });
  const spacer = document.createElement("div");
  spacer.className = "cell-head-spacer";
  const actions = document.createElement("div");
  actions.className = "cell-actions";
  actions.append(
    actionButton("↑", "Move up", () => moveCell(cell.id, -1), index === 0),
    actionButton("↓", "Move down", () => moveCell(cell.id, 1), index === active.cells.length - 1),
    actionButton("◧", "Collapse cell", () => { section.classList.toggle("collapsed"); }),
    actionButton("✕", "Delete cell", () => deleteCell(cell.id), false, "danger"),
  );
  head.append(kind, spacer, actions);
  body.appendChild(head);

  if (cell.kind === "code") {
    body.appendChild(editorFor(cell));
  } else {
    body.appendChild(markdownFor(cell));
  }

  const output = document.createElement("div");
  output.className = "output";
  output.dataset.output = cell.id;
  body.appendChild(output);
  section.append(gutter, body);
  dom.cells.appendChild(section);
  refreshOutput(cell);
}

function actionButton(label, title, onClick, disabled = false, extra = "") {
  const button = document.createElement("button");
  button.className = `icon-button ${extra}`.trim();
  button.type = "button";
  button.title = title;
  button.textContent = label;
  button.disabled = disabled;
  button.addEventListener("click", onClick);
  return button;
}

function editorFor(cell) {
  const wrap = document.createElement("div");
  wrap.className = "editor";
  const lines = document.createElement("div");
  lines.className = "line-numbers";
  const input = document.createElement("textarea");
  input.className = "code-input";
  input.spellcheck = false;
  input.value = cell.source;
  input.placeholder = "-- Lua code runs in the remote LuaJIT kernel";
  input.setAttribute("aria-label", "Lua code");
  input.addEventListener("input", () => {
    cell.source = input.value;
    updateLines(input, lines);
    save();
  });
  input.addEventListener("keydown", (event) => {
    if (event.key === "Tab" && !event.shiftKey) {
      event.preventDefault();
      insertText(input, "  ");
      cell.source = input.value;
      updateLines(input, lines);
      save();
    } else if (event.key === "Enter" && (event.shiftKey || event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      runCell(cell.id);
    }
  });
  wrap.append(lines, input);
  requestAnimationFrame(() => updateLines(input, lines));
  return wrap;
}

function markdownFor(cell) {
  const wrap = document.createElement("div");
  wrap.className = "markdown-cell";
  const edit = document.createElement("button");
  edit.className = "markdown-edit";
  edit.type = "button";
  edit.textContent = "Edit";
  const input = document.createElement("textarea");
  input.className = "markdown-input";
  input.spellcheck = false;
  input.value = cell.source;
  input.placeholder = "Write markdown…";
  input.setAttribute("aria-label", "Markdown source");
  const preview = document.createElement("div");
  preview.className = "markdown-preview";
  preview.innerHTML = renderMarkdown(cell.source);
  const beginEdit = () => {
    wrap.classList.add("editing");
    requestAnimationFrame(() => { input.focus(); input.setSelectionRange(input.value.length, input.value.length); });
  };
  const endEdit = () => {
    wrap.classList.remove("editing");
    preview.innerHTML = renderMarkdown(cell.source);
  };
  edit.addEventListener("click", beginEdit);
  preview.addEventListener("dblclick", beginEdit);
  input.addEventListener("input", () => {
    cell.source = input.value;
    save();
  });
  input.addEventListener("blur", endEdit);
  input.addEventListener("keydown", (event) => {
    if (event.key === "Escape") { event.preventDefault(); input.blur(); }
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      input.blur();
    }
  });
  wrap.append(edit, input, preview);
  return wrap;
}

function insertText(input, text) {
  const start = input.selectionStart;
  const end = input.selectionEnd;
  input.setRangeText(text, start, end, "end");
}

function refreshOutput(cell) {
  const section = cellElement(cell.id);
  if (!section) return;
  const output = section.querySelector(".output");
  output.replaceChildren();
  if (cell.output) {
    const stdout = document.createElement("pre");
    stdout.className = "stdout has-output";
    stdout.textContent = cell.output;
    output.appendChild(stdout);
  }
  if (cell.value !== undefined && cell.value !== null && cell.value !== "") {
    const row = document.createElement("div");
    row.className = "value-row";
    const label = document.createElement("span");
    label.className = "value-label";
    label.textContent = "return";
    const value = document.createElement("span");
    value.className = "value-text";
    value.textContent = cell.value;
    row.append(label, value);
    output.appendChild(row);
  }
  if (cell.error) {
    const error = document.createElement("div");
    error.className = "error-text";
    error.textContent = cell.error;
    output.appendChild(error);
  }
  if (cell.widgets?.length) {
    const widgets = document.createElement("div");
    widgets.className = "widgets";
    for (const spec of cell.widgets) widgets.appendChild(widgetFor(cell, spec));
    output.appendChild(widgets);
  }
  if (cell.scene !== undefined && cell.scene !== null) {
    const scene = document.createElement("div");
    scene.className = "scene-target";
    output.appendChild(scene);
    renderScene(scene, cell.scene);
  }
  if (!cell.output && !cell.error && (cell.value === undefined || cell.value === null || cell.value === "") && !cell.widgets?.length && (cell.scene === undefined || cell.scene === null)) {
    output.style.display = "none";
  } else {
    output.style.display = "";
  }
}

function widgetFor(cell, spec) {
  const wrap = document.createElement("div");
  wrap.className = "widget";
  const send = (event) => sendWidget(cell.id, spec.id, event);
  if (spec.kind === "slider" || spec.kind === "number") {
    const row = document.createElement("div");
    row.className = "widget-row";
    const label = document.createElement("span");
    label.className = "widget-label";
    label.textContent = spec.label || "value";
    const input = document.createElement("input");
    input.type = spec.kind === "slider" ? "range" : "number";
    input.min = spec.min ?? "";
    input.max = spec.max ?? "";
    input.step = spec.step ?? "any";
    input.value = spec.value ?? spec.min ?? 0;
    const value = document.createElement("span");
    value.className = "widget-value";
    value.textContent = String(spec.value ?? input.value);
    input.addEventListener("input", () => { value.textContent = input.value; });
    input.addEventListener("change", () => {
      value.textContent = input.value;
      send({ value: Number(input.value) });
    });
    row.append(label, input, value);
    wrap.appendChild(row);
  } else if (spec.kind === "button") {
    const button = document.createElement("button");
    button.className = "button";
    button.type = "button";
    button.textContent = spec.label || "Button";
    button.addEventListener("click", () => send({ type: "click" }));
    wrap.appendChild(button);
  } else if (spec.kind === "checkbox") {
    const label = document.createElement("label");
    label.className = "widget-checkbox";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = Boolean(spec.value);
    input.addEventListener("change", () => send({ type: "toggle", value: input.checked }));
    label.append(input, document.createTextNode(spec.label || "Enabled"));
    wrap.appendChild(label);
  } else if (spec.kind === "select") {
    const row = document.createElement("div");
    row.className = "widget-row";
    const label = document.createElement("span");
    label.className = "widget-label";
    label.textContent = spec.label || "select";
    const select = document.createElement("select");
    for (const option of spec.options || []) {
      const item = document.createElement("option");
      item.value = String(option.value ?? option.label ?? "");
      item.textContent = option.label ?? String(option.value ?? "");
      item.optionValue = option.value ?? option.label;
      if (String(option.value ?? option.label) === String(spec.value)) item.selected = true;
      select.appendChild(item);
    }
    select.addEventListener("change", () => {
      const selected = select.options[select.selectedIndex];
      send({ value: selected?.optionValue ?? select.value });
    });
    row.append(label, select);
    wrap.appendChild(row);
  } else if (spec.kind === "text") {
    const row = document.createElement("div");
    row.className = "widget-row";
    const label = document.createElement("span");
    label.className = "widget-label";
    label.textContent = spec.label || "text";
    const input = document.createElement(spec.multiline ? "textarea" : "input");
    if (!spec.multiline) input.type = "text";
    input.value = spec.value ?? "";
    input.placeholder = spec.placeholder ?? "";
    input.addEventListener("change", () => send({ value: input.value }));
    row.append(label, input);
    wrap.appendChild(row);
  } else if (spec.kind === "progress") {
    const row = document.createElement("div");
    row.className = "widget-row";
    const label = document.createElement("span");
    label.className = "widget-label";
    label.textContent = spec.label || "progress";
    const progress = document.createElement("div");
    progress.className = "widget-progress";
    const bar = document.createElement("span");
    const min = spec.min ?? 0, max = spec.max ?? 1;
    bar.style.width = `${Math.max(0, Math.min(100, ((spec.value - min) / (max - min || 1)) * 100))}%`;
    progress.appendChild(bar);
    row.append(label, progress);
    wrap.appendChild(row);
  } else if (spec.kind === "label") {
    const label = document.createElement("div");
    label.className = "widget-label-text";
    label.textContent = spec.text || spec.label || "";
    wrap.appendChild(label);
  } else if (spec.kind === "shader") {
    const shader = document.createElement("div");
    shader.className = "widget-shader";
    shader.textContent = `${spec.label || "shader"} · shader widgets render in the LÖVR desktop host`;
    wrap.appendChild(shader);
  } else {
    const unknown = document.createElement("div");
    unknown.className = "widget-label-text";
    unknown.textContent = `${spec.kind || "widget"} ${spec.label || ""}`;
    wrap.appendChild(unknown);
  }
  return wrap;
}

function runCell(id) {
  const cell = cellById(id);
  if (!cell || cell.kind !== "code") return;
  if (cell.running) return;
  cell.running = true;
  const section = cellElement(cell.id);
  section?.classList.add("running");
  const button = section?.querySelector(".run-button");
  if (button) button.disabled = true;
  if (!statusReady()) {
    queue.push({ notebookId: active.id, cellId: cell.id, code: cell.source });
    toast(connected ? "Opening the kernel…" : "Waiting for the gateway…");
    return;
  }
  transmitRun(active.id, cell);
}

function transmitRun(notebookId, cell) {
  const id = gateway.nextRequestId();
  pending.set(id, { notebookId, cellId: cell.id, kind: "run" });
  const sent = gateway.send({
    type: "run", notebook: notebookId, id, cell: cell.id, code: cell.source,
  });
  if (!sent) {
    pending.delete(id);
    cell.running = false;
    refreshOutput(cell);
    toast("Gateway is not connected", true);
  }
}

function sendWidget(cellId, widgetId, event) {
  const cell = cellById(cellId);
  if (!cell || !statusReady()) { toast("Kernel is not ready", true); return; }
  const id = gateway.nextRequestId();
  pending.set(id, { notebookId: active.id, cellId, kind: "widget" });
  const sent = gateway.send({
    type: "widget", notebook: active.id, id, cell: cell.id, widget: widgetId,
    event,
  });
  if (!sent) {
    pending.delete(id);
    toast("Gateway is not connected", true);
  }
}

function handleResult(message) {
  const request = pending.get(message.id);
  if (!request) return;
  pending.delete(message.id);
  const target = state.notebooks.find((item) => item.id === request.notebookId);
  const cell = target?.cells.find((item) => item.id === request.cellId);
  if (!cell) return;
  cell.running = false;
  if (message.ok === false) {
    cell.error = message.value || message.message || "cell failed";
    if (message.output) cell.output = request.kind === "widget" && cell.output
      ? `${cell.output}\n${message.output}` : message.output;
    cell.value = "";
    cell.scene = null;
  } else {
    cell.error = null;
    if (request.kind === "widget") {
      if (message.output) cell.output = cell.output ? `${cell.output}\n${message.output}` : message.output;
    } else {
      cell.output = message.output || "";
      cell.value = message.value ?? "";
    }
    if (message.scene !== undefined) cell.scene = message.scene;
    if (message.widgets !== undefined) cell.widgets = message.widgets;
  }
  if (target.id === active.id) {
    const section = cellElement(cell.id);
    section?.classList.remove("running");
    refreshOutput(cell);
    refreshRunButtons();
  }
  save();
}

function handleMessage(message) {
  switch (message.type) {
    case "hello":
      hello = true;
      connected = true;
      dom.runtime.textContent = message.capabilities?.runtime || "luajit";
      setConnection("connecting", "connected");
      if (!ready.has(active.id)) openKernel(active.id);
      break;
    case "open_ok":
      if (!message.notebook) break;
      ready.add(message.notebook);
      opening.delete(message.notebook);
      if (message.notebook === active.id) {
        setConnection("ready", "kernel ready");
        flushQueue();
      }
      break;
    case "closed":
      ready.delete(message.notebook);
      if (message.notebook === active.id) setConnection("connecting", "kernel closed");
      break;
    case "result":
      handleResult(message);
      break;
    case "error":
      if (message.id && pending.has(message.id)) {
        const request = pending.get(message.id);
        pending.delete(message.id);
        const target = state.notebooks.find((item) => item.id === request.notebookId);
        const cell = target?.cells.find((item) => item.id === request.cellId);
        if (cell) {
          cell.running = false;
          cell.error = message.message || "gateway error";
          if (target.id === active.id) {
            const section = cellElement(cell.id);
            section?.classList.remove("running");
            refreshOutput(cell);
          }
        }
      } else {
        toast(message.message || "Gateway error", true);
      }
      break;
    default:
      break;
  }
}

function openKernel(notebookId) {
  if (!connected || !hello || ready.has(notebookId) || opening.has(notebookId)) return;
  opening.add(notebookId);
  const sent = gateway.send({ type: "open", notebook: notebookId });
  if (!sent) opening.delete(notebookId);
}

function flushQueue() {
  if (!queue.length) return;
  const remaining = [];
  for (const item of queue) {
    if (!ready.has(item.notebookId)) { remaining.push(item); continue; }
    const target = state.notebooks.find((entry) => entry.id === item.notebookId);
    const cell = target?.cells.find((entry) => entry.id === item.cellId);
    if (!cell) continue;
    cell.running = true;
    transmitRun(item.notebookId, cell);
  }
  queue = remaining;
}

function connect(url) {
  clearTimeout(reconnectTimer);
  wsUrl = url;
  saveGatewayUrl(url);
  hello = false;
  connected = false;
  ready = new Set();
  opening = new Set();
  pending = new Map();
  queue = [];
  setConnection("connecting", "connecting");
  gateway.connect(url);
  if (dom.settingsDialog.open) dom.settingsDialog.close();
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    if (!gateway.closedByUser) connect(wsUrl);
  }, 2200);
}

function addCell(kind) {
  const cell = createCell(kind, "");
  active.cells.push(cell);
  active.updatedAt = Date.now();
  save();
  renderAll();
  const el = cellElement(cell.id);
  el?.querySelector("textarea")?.focus();
  el?.scrollIntoView({ block: "nearest" });
}

function moveCell(id, direction) {
  const index = active.cells.findIndex((cell) => cell.id === id);
  const next = index + direction;
  if (index < 0 || next < 0 || next >= active.cells.length) return;
  [active.cells[index], active.cells[next]] = [active.cells[next], active.cells[index]];
  save();
  renderAll();
}

function deleteCell(id) {
  if (active.cells.length <= 1) { toast("A notebook needs at least one cell"); return; }
  active.cells = active.cells.filter((cell) => cell.id !== id);
  save();
  renderAll();
}

function runAll() {
  for (const cell of active.cells) {
    if (cell.kind === "code") runCell(cell.id);
  }
}

function clearOutputs(notebookId) {
  const target = state.notebooks.find((item) => item.id === notebookId);
  if (!target) return;
  for (const cell of target.cells) {
    cell.output = "";
    cell.value = "";
    cell.error = null;
    cell.scene = null;
    cell.widgets = [];
    cell.running = false;
  }
  if (target.id === active.id) renderAll();
}

function restartKernel() {
  if (!connected) { toast("Gateway is not connected", true); return; }
  if (!confirm("Restart the kernel? All variables in this notebook will be lost.")) return;
  ready.delete(active.id);
  pending = new Map();
  queue = [];
  const sent = gateway.send({ type: "restart", notebook: active.id });
  if (!sent) { toast("Gateway is not connected", true); return; }
  clearOutputs(active.id);
  setConnection("connecting", "restarting…");
}

function newNotebook() {
  const notebook = createNotebook(uniqueNotebookName(state, "Untitled.luanb"));
  state.notebooks.push(notebook);
  state.activeId = notebook.id;
  active = notebook;
  save();
  renderAll();
  openKernel(active.id);
  dom.title.focus();
  dom.title.select();
}

function deleteNotebook() {
  if (state.notebooks.length <= 1) { toast("Cannot delete the last notebook"); return; }
  if (!confirm(`Delete “${active.name}”?`)) return;
  state.notebooks = state.notebooks.filter((item) => item.id !== active.id);
  state.activeId = state.notebooks[0].id;
  active = state.notebooks[0];
  save();
  renderAll();
  openKernel(active.id);
}

function importFile(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const imported = importNotebook(String(reader.result));
      imported.name = uniqueNotebookName(state, imported.name);
      state.notebooks.push(imported);
      state.activeId = imported.id;
      active = imported;
      save();
      renderAll();
      toast("Notebook imported");
    } catch (error) {
      toast(`Import failed: ${error.message}`, true);
    }
  };
  reader.onerror = () => toast("Could not read the file", true);
  reader.readAsText(file);
}

function exportFile() {
  const blob = new Blob([exportNotebook(active)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = active.name.endsWith(".luanb") ? active.name : `${active.name}.luanb`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

// Events
dom.sidebarToggle.addEventListener("click", () => dom.sidebar.classList.toggle("open"));
dom.settings.addEventListener("click", () => {
  dom.wsUrl.value = wsUrl;
  dom.settingsDialog.showModal();
  dom.wsUrl.focus();
});
document.getElementById("cancel-settings").addEventListener("click", () => dom.settingsDialog.close());
dom.settingsForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const url = dom.wsUrl.value.trim();
  if (!/^wss?:\/\//i.test(url)) { toast("Use a ws:// or wss:// URL", true); return; }
  connect(url);
  toast("Connecting to the kernel…");
});
dom.newNotebook.addEventListener("click", newNotebook);
dom.deleteNotebook.addEventListener("click", deleteNotebook);
dom.addCode.addEventListener("click", () => addCell("code"));
dom.addMarkdown.addEventListener("click", () => addCell("markdown"));
dom.importNotebook.addEventListener("click", () => dom.fileInput.click());
dom.fileInput.addEventListener("change", () => {
  const file = dom.fileInput.files?.[0];
  if (file) importFile(file);
  dom.fileInput.value = "";
});
dom.exportNotebook.addEventListener("click", exportFile);
dom.restart.addEventListener("click", restartKernel);
dom.runAll.addEventListener("click", runAll);
dom.title.addEventListener("change", () => {
  let name = dom.title.value.trim() || "Untitled.luanb";
  if (!name.endsWith(".luanb")) name += ".luanb";
  active.name = name;
  active.updatedAt = Date.now();
  dom.title.value = name;
  save();
  renderAll();
});
dom.title.addEventListener("keydown", (event) => {
  if (event.key === "Enter") { event.preventDefault(); dom.title.blur(); }
});
window.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
    event.preventDefault();
    save();
    toast("Saved locally");
  }
});
window.addEventListener("resize", () => redrawScenes());
window.addEventListener("beforeunload", () => saveState(state));

gateway = new Gateway({
  onStatus(status, detail) {
    if (status === "connecting") setConnection("connecting", "connecting");
    else if (status === "error") setConnection("error", "connection error");
    else if (status === "closed") setConnection("connecting", "offline");
    else if (status === "offline") setConnection("", "offline");
    if (status === "error" && detail) console.warn(detail);
  },
  onOpen() {
    hello = false;
    connected = true;
    setConnection("connecting", "connected");
  },
  onClose() {
    connected = false;
    hello = false;
    for (const request of pending.values()) {
      const target = state.notebooks.find((item) => item.id === request.notebookId);
      const cell = target?.cells.find((item) => item.id === request.cellId);
      if (cell) {
        cell.running = false;
        cell.error = "Connection to the kernel was lost.";
      }
    }
    for (const item of queue) {
      const target = state.notebooks.find((entry) => entry.id === item.notebookId);
      const cell = target?.cells.find((entry) => entry.id === item.cellId);
      if (cell) cell.running = false;
    }
    pending = new Map();
    queue = [];
    ready = new Set();
    opening = new Set();
    setConnection("", "offline");
    if (active.id) renderAll();
    scheduleReconnect();
  },
  onMessage: handleMessage,
});

renderAll();
setConnection("connecting", "connecting");
gateway.connect(wsUrl);
