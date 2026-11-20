# lua-notebooks

**Notebooks with a 3D viewport.** A LÖVR-hosted notebook environment for Lua,
built for interactive science, visualization, and game development.

This is an early first milestone, not a JupyterLab replacement yet. The goal is
a native notebook that treats a real-time scene as a first-class output.

## Status

Working in this milestone:

- native LÖVR window with notebook tabs and cells
- a tiny editable cell UI (keyboard input, backspace, newline, tab)
- **one persistent Lua kernel per notebook**, each in a separate LÖVR thread on
  desktop and inline on the web
- cell execution with captured `print`/`io.write`, errors, and return values
- a **3D cube output** rendered by the host, never by the kernel
- a **luaplotlib scene renderer**: line/scatter/bar/hist scenes, axes, grid,
  title, labels, and category ticks
- a **render-target extension platform**: manifest validation, filesystem
  discovery, local pointer/key routing, F8 reload, a filesystem watcher, and
  two built-in extensions (`cube`, `grid`)
- F5 run, cell selection, add-cell, mouse tabs, scroll
- offline LÖVR 0.19 API docs, examples, and LuaLS annotations under `docs/lovr/`
- noninteractive smoke tests that exercise the kernel and renderer

Implemented after the original milestone:

- native file dialogs on Linux, Windows, and macOS;
- extension permissions, sandbox gating, and per-extension toggles;
- a standalone stdio JSON-RPC LSP server;
- Windows process-kernel CI;
- gateway token authentication;
- offscreen visual regression in CI;
- LuaRocks publishing and LÖVR archive artifacts;
- an embedded Neovim cell/notebook editor over msgpack-RPC;
- configurable translucent light theme.

Remaining limits:

- OS sandboxing for user extensions is Linux/bubblewrap-specific;
- semantic LSP analysis is local and partial;
- TeX/MathJax-quality math is not implemented;
- Neovim editing requires `nvim` on PATH and is Linux/macOS POSIX-tested;
- visual baselines use a tolerance for software-renderer variance.

## Requirements

- LÖVR **0.19.x** (`lovr` on PATH; this machine uses `lovr-bin` 0.19.0)
- LuaJIT on desktop (bundled with LÖVR; `luajit` is used for the pure-Lua
  tests)
- PUC Lua 5.1 on the web (LÖVR’s WASM runtime; no JIT)
- a GPU with a working Vulkan/OpenGL driver for LÖVR

## Web (experimental)

LÖVR’s web exporter builds against **PUC Lua 5.1** and disables threads and
processes. lua-notebooks detects this with `notebook/runtime.lua` and switches
to an inline kernel supervisor, so the same notebook/engine code runs without
LuaJIT.

What the client-side web path implements:

- notebook UI, cells, markdown, scenes, built-in extensions, and the inline
  Lua 5.1 kernel;
- captured output, errors, return values, widget state, and 3D scene outputs.

The inline path is Lua 5.1-tested, but full browser rendering is currently
blocked on the upstream LÖVR/WebGPU issue noted below; the remote bridge has
been validated independently.

Limitations:

- no process kernels, `ffi`, or LÖVR threads;
- the external LSP worker is disabled;
- bubblewrap-sandboxed user extensions are unavailable;
- heavy numerical cells are slower because there is no JIT.

The pure-Lua test suite is expected to pass on Lua 5.1:

```sh
make test-lua51 LUA=lua5.1
```

### Browser front-end

A browser-only front-end that does not use LÖVR or WebGPU lives in
[`webapp/`](webapp/):

```sh
luajit webapp/serve.lua --port 8010
```

It connects to the same gateway over a native WebSocket and renders the
notebook shell, widgets, and `luaplotlib`/scene outputs locally. See
[webapp/README.md](webapp/README.md). This path is independent of the broken
LÖVR 0.19 web runtime.

See [docs/web.md](docs/web.md) for the LÖVR build steps and constraints.

A remote-kernel path is also available: a local WebSocket gateway, a
transport-agnostic `RemoteSupervisor`, a desktop remote mode, and an
Emscripten browser bridge in `web/`. It exposes the full LuaJIT/FFI stack to a
front-end. See [docs/remote.md](docs/remote.md) and [web/README.md](web/README.md).

The remote WebSocket bridge has been validated end to end in headless Firefox
and Chromium. Full notebook rendering is currently blocked on an upstream
LÖVR/WebGPU issue, documented in [web/README.md](web/README.md): Emscripten
5.0.2 crashes on a minimal graphics project, while Emscripten 4.0.23 fails
LÖVR's text render pipeline in Chromium.

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
| `p` | run selected cell in Vim normal mode |
| `Alt+P` | run selected cell, then select the next cell |
| `F5` or run icon | execute selected cell |
| `b` / `a` | insert a code cell below / above |
| `M` | insert a markdown cell below |
| `+` icon | insert a code cell below the focused cell |
| `F6` | save active notebook to the LÖVR save directory |
| `F7` | load it back |
| `Tab` | insert two spaces |
| `Left` / `Right` | move the caret |
| `Home` / `End` | start / end of line |
| `Backspace` / `Delete` | delete before / after the caret |
| `Enter` | newline |
| `Up` / `Down` | previous / next cell |
| mouse wheel | scroll (or zoom a 3D surface under the pointer) |
| drag in 3D surface | orbit the extension camera |
| `F8` | hot-reload the focused extension renderer |
| `F9` | reload extensions from the save directory |
| `F10` | open/close the extension browser; click a row to enable/disable |
| `F11` | open/close the heading outline |
| `Ctrl+Space` | open Lua completion for the selected code cell |
| `Ctrl+H` | show hover help for the trailing identifier |
| `Ctrl+G` | jump to a local/function definition of the trailing identifier |
| `Ctrl+Shift+R` | rename the trailing identifier across code cells |
| `F1` | open/close the command palette |
| `F2` | open the hierarchical notebook filetree |
| `F3` | toggle Vim mode (on by default) |
| `F4` | toggle Zen mode: hide top bar and footer, show only cells |
| `Ctrl+Shift+S` | save a PNG screenshot of the offscreen notebook canvas |
| `Ctrl+Shift+T` | toggle light/dark theme; persisted |
| `+` / `-` or `Ctrl++` / `Ctrl+-` | zoom the whole UI; `0` resets |
| `?` or `F12` | open/close the keybindings cheatsheet |
| click a markdown heading arrow | collapse/expand following cells |
| drag / wheel in 3D | orbit / zoom the focused extension |
| tabs / **+ Cell** | switch notebook / add cell |

The welcome notebook has runnable cells for hello, a loop, a 3D cube scene, a
luaplotlib scene, a grid extension, and widgets. The second notebook has an independent kernel
and global state.

## File tree and Vim mode

**F2** opens a hierarchical list of saved notebooks under `notebooks/`.
Clicking a folder expands it, clicking a notebook opens it, `+ New notebook`
creates one, `+ Folder` creates a folder, `✎` renames one, and `×` asks for
confirmation before deleting one.

Vim mode is **on by default** and is shown in the footer:

- `Escape` enters normal mode;
- `i`/`a` enter insert mode;
- `j`/`k` move between cells;
- `o` adds a code cell and enters insert mode;
- `x` deletes the final character of the selected code cell;
- **F3** toggles Vim mode.

This is a small subset of Vim, not a full Vim implementation.

## LSP core

A transport-independent JSON-RPC LSP core now exists under `notebook/lsp/`.
It handles initialization, cell open/change/close, diagnostics, completion,
and hover, with a transport-independent client and persisted cell IDs. It is
not yet wired to a LÖVR worker thread or a full semantic scope analyzer; see
[`docs/lsp.md`](docs/lsp.md).

## Themes

**Ctrl+Shift+T** toggles a persisted light/dark UI theme. The light theme
remaps the notebook's HSL lightness while preserving syntax hues; charts and 3D
surfaces keep their own renderer colors.

## Zen mode

**F4** toggles Zen mode. It hides the title/tab/toolbar row and the footer,
leaving only notebook cells. Escape also leaves Zen. Overlays and the command
palette still work when explicitly opened.

## Shader widgets

Kernels can request a live shader preview:

```lua
widgets.shader({ label = "Star Nest", shader = "star_nest", height = 180 })
```

The host compiles the fragment shader once, sends a `time` uniform, and clips it
to the widget rectangle. The included `star_nest` preset is the MIT-licensed
Star Nest shader by Pablo Román Andrioli, adapted from the shooter project.
Custom fragment source can also be supplied through `shader`.

## Undo tree

Edits are stored as a branching history instead of a single linear stack. Undo
after a change and start a new edit to create a branch; `:history` shows the
tree, and `g-`/`g+` walk older/newer states.

## Markdown editing

Markdown cells are fully editable: typing, backspace/delete, newline, cursor
movement, and Vim operations share the code-cell editing path.

## Markdown preview

Markdown cells show formatted text when unfocused: heading markers, emphasis,
inline code, links, and list markers are removed for display. Selecting the cell
returns to editable source. Display math renders in both states.

## Notebook title

The first `#` heading in a markdown cell is the notebook title. Tabs show this
title, not the `.luanb` filename; the title updates as the heading is edited.
`##` and lower headings do not become the title. The title bar is 40px high.

## Cell labels

Cells no longer have a `CODE In [x]` header row. A compact number is drawn at
the end of the first source line, colored by cell kind and running state. This
removes one full line per cell while keeping the number visible.

## Cell focus

Code and output are one cell. Clicking a plot, surface, widget, or text output
selects the parent cell and draws a unified focus border around the whole cell.
Clicking the source returns focus to editing and clears output focus.

The filetree and outline are **overlays, not a persistent sidebar**. They are
closed at startup and only open from F2/F11 or the command palette. Escape
closes any open overlay. The icon rail visible in desktop screenshots is the
Wayland compositor dock, outside the notebook window.

## Math and collapsible headings

Markdown supports a small inline LaTeX-to-Unicode subset (`$E = mc^2$`,
`$\alpha + \beta$`, simple fractions/roots). Headings with a `▾`/`▸` marker
collapse following cells when clicked. See [`docs/math.md`](docs/math.md) and
[`docs/collapsible-headings.md`](docs/collapsible-headings.md).

## User extension sandbox

`.json` extensions are declarative display lists. `.lua` extensions run once
inside `bwrap --unshare-all` with read-only `/usr`, no `/home`, no network, and
a 3s/256MB limit; only their static display-list result reaches the host.
`tests/extension_sandbox.sh` probes `/etc/passwd`, `/home`, and the result.

## User extensions

Drop a `.lua` extension module into:

```text
~/.local/share/LOVR/lua-notebooks/user-extensions/
```

Press **F9** to reload them. User files override built-in extensions with the
same id. This is a local install path, not a marketplace. User extensions are loaded
with a restricted environment: no `os`, `io`, `package`, `debug`, `require`,
`loadstring`, or filesystem access. They receive read-only graphics/timer
proxies, math/string/table, and the vector/matrix constructors. This is a
best-effort Lua environment, not an OS sandbox.

## Package

```sh
make package
lovr dist/lua-notebooks.zip
```

The archive contains `conf.lua`, `main.lua`, `notebook/`, `kernel/`, `ui/`, and
`extensions/`. It runs in thread mode. Process mode needs a real project
directory because the child is launched from `lovr.filesystem.getSource()`.

## Physical input testing

On Wayland/Hyprland, `ydotool` can drive real key events when `/dev/uinput` is
accessible:

```sh
ydotoold --socket-path /tmp/ydotool.sock &
YDOTOOL_SOCKET=/tmp/ydotool.sock ydotool key 108:1 108:0  # Down
```

This was used to move selection to the final cell; two captures one second
apart showed the scroll position stable and the last cell fully visible.

The repeatable check is:

```sh
./scripts/input-smoke.sh
```

It launches a seat session, sends six Down keys, captures two frames one second
apart, and fails if the stable-frame difference exceeds 5000 pixels.

## Status

See [`docs/roadmap.md`](docs/roadmap.md) for the implemented surface and the
remaining gaps.

## Tests

`make test` runs the pure model, widget, engine, remote-supervisor,
process-kernel, sandbox, and editor suite on LuaJIT. `make test-lua51
LUA=lua5.1` runs the Lua 5.1-compatible subset. `make test-remote` starts the
WebSocket gateway and executes a cell with a real client. CI runs all three;
graphics, input, and visual smokes are manual because they need a display and
seat.

## Visual smoke

```sh
./scripts/visual-smoke.sh       # coarse live-window check
./scripts/visual-baseline.sh    # pixel baselines from the offscreen canvas
./scripts/visual-baseline.sh --update
```

`visual-baseline.sh` renders the notebook through an offscreen rgba8 canvas,
reads it back from the GPU, and compares 50%-scale PNGs for cells 4, 6, and 7.
It is display-dependent and not part of `make test`.

The offscreen canvas is also what makes screenshots independent of the
compositor and window stacking.

## LuaRocks

```sh
luarocks make lua-notebooks-1.12.0-1.rockspec
lua-notebooks
```

The rockspec installs the app source under the LuaRocks share tree and a
`lua-notebooks` launcher under its bin directory.

```sh
make rock
luarocks install lua-notebooks-1.12.0-1.src.rock
```

Publishing to a remote rock server is intentionally not automated.

## Local install

```sh
make install
lovr ~/.local/share/lua-notebooks
```

`PREFIX=/path make install` installs elsewhere. To also create a local desktop
entry:

```sh
make install-desktop
```

This still does not install system-wide.

## Process kernels

Threads are the default. An experimental process backend is available:

```sh
LUANB_KERNEL_MODE=process lovr .
```

Each notebook then gets a plain-LuaJIT child with a file-backed job/result
channel. POSIX and Windows spawn/stop commands are selected by platform; only
the POSIX path is runtime-verified here. See [`docs/process-kernels.md`](docs/process-kernels.md) for the
protocol, timeout behavior, and limitations.

## Status

See [`docs/roadmap.md`](docs/roadmap.md) for the implemented surface and the
remaining gaps.

## Tests

```sh
make test                 # pure-Lua JSON/model tests
LUANB_SMOKE=1 lovr .      # run first cell through a real kernel, then quit
LUANB_SMOKE_SCENE=1 lovr . # run the 3D cell, draw the viewport, then quit
LUANB_SMOKE_PLOT=1 lovr .  # run the luaplotlib scene cell, draw it, then quit
LUANB_SMOKE_GRID=1 lovr .   # run the grid extension cell, then quit
LUANB_SMOKE_WIDGET=1 lovr . # run the widget cell, then quit
LUANB_SMOKE_WIDGET_EVENT=1 lovr . # run the widget cell and change a slider
LUANB_SMOKE_SAVE=1 lovr .   # save/load the active notebook, then quit
LUANB_QA_CELL=6 lovr .      # run one cell and keep the window open for visual QA
LUANB_SMOKE_RELOAD=1 lovr . # reload the cube renderer module, then quit
LUANB_SMOKE_WATCH=1 lovr .  # touch cube.lua and verify filesystem hot reload
LUANB_SMOKE_INPUT=1 lovr .  # programmatic pointer drag on the cube surface
LUANB_KERNEL_MODE=process LUANB_SMOKE=1 lovr . # process kernel
LUANB_KERNEL_MODE=process LUANB_SMOKE_PROCESS_CRASH=1 lovr . # crash recovery
```

`docs/lovr/` is a vendored, offline LÖVR 0.19 reference: API metadata, generated
LuaLS annotations, guides, examples (media pruned), and notes on `lovr-ent`,
`lite-lovr`, and hot reload. `.luarc.json` points LuaLS at it.

## Architecture

```text
LÖVR host
  ├── notebook UI / 2D editor / 3D viewport
  ├── supervisor
  │     ├── desktop: thread + channels → notebook kernel (Lua state)
  │     ├── web: inline queue          → notebook kernel (5.1 env)
  │     └── remote: WebSocket          → LuaJIT kernel gateway
  └── scene renderer (host-only graphics)

kernel
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

## Visual CI

CI runs an offscreen LÖVR render smoke for QA cells and fails on blank captures. Pixel-level baseline comparison remains a manual/local check because GPU and font rendering differ across runners.

## Visual CI

CI renders QA cells offscreen with LÖVR 0.19.0 and compares them to committed pixel baselines. A 25,000-pixel tolerance absorbs software-renderer/font variance; structural regressions still fail.

## Stability

The notebook format, extension contract, gateway flags, and LSP capabilities are covered by [docs/stability.md](docs/stability.md).

## Transparency

Use the command palette action **Toggle notebook transparency** to switch the light notebook between opaque white and a translucent WezTerm-like surface. LÖVR is configured with `t.window.transparent = true`; the opacity setting is stored in `opacity.txt` in the save directory.

## Neovim editor (experimental)

The `spike/nvim-ui` branch embeds a headless Neovim instance and renders its
`ext_linegrid` UI in LÖVR. Press **Alt+E** or use the command palette action **Neovim cell editor**.

- `F10` writes the buffer back to the current cell;
- `F9` discards and closes;
- the editor starts in insert mode;
- `Escape` enters Vim normal mode for full Vim keybindings.

Requirements: `nvim` on `PATH`. The bridge uses msgpack-RPC over a local TCP
socket, not `luv` or `lua-mp`.

## Search

Press **Ctrl+F** to search every cell. Use Up/Down and Enter or click a result to select the matching cell and cursor position.

## Kernel commands

The command palette exposes **Restart current kernel**, **Clear all cell outputs**, **Run all code cells**,
**Move selected cell up/down**, **Duplicate selected cell**, and **Export notebook
as Markdown**. `Ctrl+Shift+K` restarts the current kernel.
