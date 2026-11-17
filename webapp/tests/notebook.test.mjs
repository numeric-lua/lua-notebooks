import test from "node:test";
import assert from "node:assert/strict";
import {
  createCell, createNotebook, exportNotebook, importNotebook, uniqueNotebookName,
} from "../js/notebook.js";

test("exports and imports a v1 notebook", () => {
  const notebook = createNotebook("demo.luanb", [
    createCell("markdown", "# Demo"),
    createCell("code", "return 42"),
  ]);
  const restored = importNotebook(exportNotebook(notebook));
  assert.equal(restored.name, "demo.luanb");
  assert.equal(restored.cells.length, 2);
  assert.equal(restored.cells[1].kind, "code");
  assert.equal(restored.cells[1].source, "return 42");
});

test("rejects malformed notebooks", () => {
  assert.throws(() => importNotebook("{}"), /v1/);
  assert.throws(() => importNotebook('{"version":1,"name":"x","cells":[{"kind":"bad"}]}'), /Invalid cell/);
});

test("generates unique notebook names", () => {
  const state = { notebooks: [createNotebook("Untitled.luanb")] };
  assert.equal(uniqueNotebookName(state, "Untitled.luanb"), "Untitled-2.luanb");
  state.notebooks.push(createNotebook("Untitled-2.luanb"));
  assert.equal(uniqueNotebookName(state, "Untitled.luanb"), "Untitled-3.luanb");
});

test("cell ids are unique", () => {
  const ids = new Set(Array.from({ length: 50 }, () => createCell().id));
  assert.equal(ids.size, 50);
});
