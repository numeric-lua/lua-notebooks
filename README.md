# lua-notebooks

**Notebooks with a 3D viewport.** A LÖVR-hosted notebook environment for Lua,
built for interactive science, visualization, and game development.

This is an early first milestone, not a JupyterLab replacement yet. The goal is
a native notebook that treats a real-time scene as a first-class output.

## Status

Working in this milestone:

- native LÖVR window with notebook tabs and cells
- a tiny editable cell UI (keyboard input, backspace, newline, tab)
- **one persistent Lua kernel per notebook**, each in a separate LÖVR thread
- cell execution with captured `print`/`io.write`, errors, and return values
- a **3D cube output** rendered by the host, never by the kernel
- a **luaplotlib scene renderer**: line/scatter/bar/hist scenes, axes, grid,
  title, labels, and category ticks
- a **render-target extension surface**: one `Pass` + `Texture` per scene cell,
  composited into the notebook; the first extension is `extensions/cube.lua`
- F5 run, cell selection, add-cell, mouse tabs, scroll
- offline LÖVR 0.19 API docs, examples, and LuaLS annotations under `docs/lovr/`
- noninteractive smoke tests that exercise the kernel and renderer

Not yet implemented:

- notebook open/save UI (a JSON document model exists)
- full text editor features, syntax highlighting, undo, IME
- process-level kernel isolation (threads currently)
- extension pointer/event protocol and hot reload
- external extension loading with permissions
- a luaplotlib scene **backend** (the scene IR and LÖVR renderer are working;
  the SVG and LÖVR backends now share the scene model)
- package distribution / single-file build

## Requirements

- LÖVR **0.19.x** (`lovr` on PATH; this machine uses `lovr-bin` 0.19.0)
- LuaJIT (bundled with LÖVR; `luajit` is used for the pure-Lua tests)
- a GPU with a working Vulkan/OpenGL driver for LÖVR

## Run

```sh
cd ~/Códigos/numeric-lua/lua-notebooks
lovr .
```

Controls:

| input | action |
| --- | --- |
| click cell | select |
| type | append to selected code cell |
| `F5` or **Run** | execute selected cell |
| `Tab` | insert two spaces |
| `Backspace` | delete last code point |
| `Enter` | newline |
| `Up` / `Down` | previous / next cell |
| mouse wheel | scroll |
| tabs / **+ Cell** | switch notebook / add cell |

The welcome notebook has four runnable cells: hello, a loop, a
`return { scene = "cube" }` cell, and a luaplotlib-style line/scatter scene. The second notebook has an independent kernel
and global state.

## Tests

```sh
make test                 # pure-Lua JSON/model tests
LUANB_SMOKE=1 lovr .      # run first cell through a real kernel, then quit
LUANB_SMOKE_SCENE=1 lovr . # run the 3D cell, draw the viewport, then quit
LUANB_SMOKE_PLOT=1 lovr .  # run the luaplotlib scene cell, draw it, then quit
```

`docs/lovr/` is a vendored, offline LÖVR 0.19 reference: API metadata, generated
LuaLS annotations, guides, examples (media pruned), and notes on `lovr-ent`,
`lite-lovr`, and hot reload. `.luarc.json` points LuaLS at it.

## Architecture

```text
LÖVR host
  ├── notebook UI / 2D editor / 3D viewport
  ├── supervisor
  │     ├── thread + channels  → notebook 1 kernel (Lua state)
  │     └── thread + channels  → notebook 2 kernel (Lua state)
  └── scene renderer (host-only graphics)

kernel thread
  └── executes cells, captures output, returns text/scene descriptions
```

Kernel threads have no `lovr.graphics` access. They return data; the host alone
draws. That boundary is what makes it possible to isolate kernels later and to
turn extension outputs into render-target surfaces.

See [`docs/architecture.md`](docs/architecture.md) for the extension and
luaplotlib backend design.

## License

BSD-3-Clause for this project. Vendored LÖVR documentation is covered by its
upstream licensing; example code is CC0 per the LÖVR docs README. See
`docs/lovr/README.md`.
