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
- a **luaplotlib scene renderer**: Cartesian line/scatter/bar/hist and polar
  line/scatter/bar, heatmap, contour, quiver, and streamplot scenes, axes,
  rings/spokes, grid, title, labels, polar colourbars, category ticks, bounded
  block sampling for large polar fields, shared quiver scale/pivot/decimation
  geometry, and frame-clipped streamplot polyline/arrow geometry with
  solid/dashed/dotted/arrow-only styles across the live viewport, SVG export,
  and browser
- a **render-target extension platform**: manifest validation, filesystem
  discovery, local pointer/key routing, F8 reload, a filesystem watcher, and
  two built-in extensions (`cube`, `grid`)
- F5 run, cell selection, add-cell, mouse tabs, scroll
- offline LÖVR 0.19 API docs, examples, and LuaLS annotations under `docs/lovr/`
- noninteractive smoke tests that exercise the kernel and renderer

Implemented after the original milestone:

- Markdown pipe tables, nested lists, italic emphasis, grouped blockquotes, and
  literal or Lua-pattern notebook find/replace;
- closable notebook tabs with an unsaved-changes guard and kernels that stay
  attached to their notebook across tab changes;
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
- Neovim editing requires `nvim` on PATH; Linux/macOS use a private Unix-socket
  transport, Windows falls back to TCP;
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
notebook shell, widgets, and `luaplotlib`/scene outputs locally: Cartesian
line/scatter/bar/hist with categorical ticks and explicit bar widths, polar
line/scatter/bar, heatmap, contour, quiver, and streamplot scenes with an
optional colourbar on the shared circular frame, and the built-in
`cube`/`grid` strings. Quiver arrows and streamplot paths/heads are clipped to
the circle; quivers use the same scale, pivot, normalization, and decimation
rules as the desktop and export renderers, and streamplots draw the integrated
polylines and mid-line heads from the same luaplotlib IR. Streamplot paths are
cut at the frame in the shared Lua and JavaScript geometry, support
solid/dashed/dotted/`none` strokes, and report both source and visible
point/run/arrow counts. Markdown previews include cell-scoped unique heading anchors and
permalink links, centered display-math blocks, clickable task checkboxes, and
fenced code blocks with language badges and **Copy** controls.
Heatmap fields larger than 4096 matrix cells are sampled into covering blocks
before painting, so the live frame, the SVG export, and the Canvas renderer stay
bounded without leaving gaps in the annulus.
`webapp/js/polar.js` mirrors `notebook/polar.lua`, and shared fixtures are
checked by both `tests/polar.lua` and the Node suite so the browser, desktop,
and export keep the same rmax, tick, label, projection, sampling, bar-wedge,
heatmap-cell, contour, colourbar, quiver, streamplot, and large-field behavior.
See [webapp/README.md](webapp/README.md). This path is
independent of the broken LÖVR 0.19 web runtime.

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

Open a notebook at startup by passing its `.luanb` path:

```sh
lovr . /path/to/notebook.luanb
# or from the installed command:
lua-notebooks /path/to/notebook.luanb
```

Pass more than one path to open several notebooks as tabs:

```sh
lua-notebooks santa-2026.luanb enveda-casmi26.luanb
```

External notebooks are read with `io.open`; F6 saves them back to the same
path.

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
| `F11` | open/close the filterable heading outline |
| `Ctrl+Space` | open Lua completion for the selected code cell |
| `Ctrl+Shift+F` | search all open notebooks |
| `Ctrl+H` | replace in the current notebook (`Alt+R` toggles Lua patterns) |
| `Ctrl+G` | open the notebook link graph |
| `Ctrl+Shift+R` | rename the trailing identifier across code cells |
| `Ctrl+T` | open/close the filterable tag index overlay |
| `Ctrl+W` | close the current notebook tab (prompts when unsaved) |
| `Ctrl+Alt+T` | reopen the last closed notebook tab |
| `Ctrl+Alt+W` | close other clean tabs; unsaved tabs stay open |
| `Ctrl+Shift+E` | show/hide per-cell execution timing |
| `Ctrl+Shift+I` | open/close notebook statistics |
| `Ctrl+Shift+O` | expand/collapse the selected cell's long output |
| `Ctrl+Shift+C` | copy the selected cell source |
| `Ctrl+V` | paste the clipboard at the caret |
| `Ctrl+Alt+C` | copy the selected cell's text output or error |
| `Ctrl+Alt+X` | clear the selected cell's output |
| `Ctrl+Shift+F5` | restart the current kernel and run every code cell |
| `Ctrl+Alt+Enter` | run the selected cell and every code cell below it |
| `Shift+Enter` | run the selected cell and select the next cell |
| `Alt+Enter` | run the selected cell and insert a new code cell below |
| `Ctrl+Alt+R` | clear the selected output and rerun the cell |
| `Ctrl+Alt+Up` | run the selected cell and every code cell above it |
| `Ctrl+Alt+G` | jump to a cell by number |
| `Ctrl+Alt+L` | jump to a line in the selected cell |
| `Ctrl+Alt+S` | save every dirty notebook |
| `Ctrl+Alt+K` | restart every notebook kernel |
| `Alt+D` | duplicate the selected cell |
| `Ctrl+/` | toggle a `--` comment on the current line |
| `Alt+Shift+Up` / `Alt+Shift+Down` | move the current line up / down |
| `Ctrl+Shift+D` | duplicate the current line |
| `Ctrl+Left` / `Ctrl+Right` | move by word |
| `Ctrl+Backspace` / `Ctrl+Delete` | delete the previous / next word |
| `Ctrl+Home` / `Ctrl+End` | jump to cell start / end |
| `Ctrl+J` | join the current line with the next |
| `Ctrl+]` / `Ctrl+[` | indent / outdent the current line |
| `Alt+Up` / `Alt+Down` | move the selected cell up / down |
| `Ctrl+Shift+Up` / `Ctrl+Shift+Down` | jump to the previous / next Markdown heading |
| `F1` | open/close the command palette |
| `F2` | open the sortable, keyboard-navigable notebook filetree |
| `F3` | toggle Vim mode (on by default) |
| `F4` | toggle Zen mode: hide top bar and footer, show only cells |
| `Ctrl+Shift+S` | save a PNG screenshot of the offscreen notebook canvas |
| `Ctrl+Shift+T` | toggle light/dark theme; persisted |
| `+` / `-` or `Ctrl++` / `Ctrl+-` | zoom the whole UI; `0` resets |
| `?` or `F12` | open/close the keybindings cheatsheet |
| click a markdown heading arrow | collapse/expand following cells |
| drag / wheel in 3D | orbit / zoom the focused extension |
| tabs / **+ Cell** | switch notebook / add cell |

The welcome notebook has runnable cells for hello, a loop, a 3D cube scene,
Cartesian and polar luaplotlib scenes (including polar quiver, streamplot, and
clipped dashed streamplot fields), a grid extension, and widgets. The second notebook has an independent
kernel and global state.

## File tree and Vim mode

**F2** opens a hierarchical list of saved notebooks under `notebooks/`.
Clicking a folder expands it, clicking a notebook opens it, `+ New notebook`
opens a name prompt and creates the notebook in the selected folder (or the
root), and `+ Folder` creates a subfolder there. The command palette adds
**Move current notebook to folder…**, **Duplicate current notebook**, **Reveal
current notebook in filetree**, and **Rename notebook title…**; reveal expands
the active notebook's ancestor folders. Folders and notebooks both expose `✎`
rename and `×` delete actions; folder deletion is limited to empty folders and
asks for confirmation.
The command palette adds **Expand all filetree folders** and **Collapse all
filetree folders**. PageUp/PageDown move through longer trees, while Home/End
jump to the first/last row. The **Sort** button cycles **A→Z**, **Z→A**,
and **Recent** (newest notebook files first); the choice persists in
`tree_sort.txt`. The `filter:` field narrows the tree as you type: matching is a
case-insensitive substring over notebook filenames, folders with a matching
descendant stay visible even when collapsed, and Up/Down move the highlighted
row, Left/Right collapse or expand a folder, Home/End jump to the first/last
row, Enter opens a file or toggles a folder, and Escape or F2 closes the tree.

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
strikethrough, inline code, links, and list markers are removed for display.
Selecting the cell returns to editable source. Display math renders in both
states. Nested bullets, ordered items, and checklists keep their indentation.
Pipe tables preview as aligned rows with cell dividers; the static HTML and
browser front-end emit a real `<table>` with left/center/right alignment from
the delimiter row. Italic (`*text*`, `_text_`), bold, strikethrough, and grouped
blockquotes render consistently in the preview, export, and browser, including
nested `>` depths. Checklist items (`- [x] done`, `- [ ] todo`) preview as
clickable `[x]`/`[ ]` markers, thematic breaks (`---`, `***`, `___`) preview as
a rule, and both build as disabled checkboxes/rules in the static HTML and
browser front-end.

Highlight `==text==` renders as plain text in the live preview and as `<mark>` in
the static export and browser. Bare `http://` and `https://` URLs become links in
the export and browser (not inside inline code or another link), and trailing
sentence punctuation stays outside the anchor. Backslash escapes keep Markdown
punctuation literal (`\*`, `\_`, an escaped backtick, `\[`, `\]`, `\(`, `\)`,
`\#`, `\+`, `\-`, `\.`, `\!`, `\|`, `\~`, `\=`, and `\\`) in all three
renderers.

Footnotes use `[^label]` for a reference and a single-line `[^label]: text`
definition in the same Markdown cell. The preview shows numbered references and
a `↳` definition line; the static export and browser emit superscript links,
an endnotes section numbered in first-reference order, and per-note backlinks.
Definitions inside fenced code or inline code stay literal, and a reference
without a definition remains literal too.

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
process-kernel, sandbox, editor, filetree filtering/sorting/keyboard navigation,
workflow shortcut dispatch, run-next/run-insert/clear-rerun, run-above, paste,
notebook naming/move/duplicate/title/reveal, save/restart-all, bulk output
folding, line/word editing, join, comment/duplicate/indent, filetree folder
create/rename/delete, tag/heading filtering, Markdown
nested quotes/callouts/definition lists/tables/nesting/
emphasis/highlight/autolink/escape/footnote/regex, polar/heatmap/contour/
quiver/streamplot/colourbar/clipping export parity, and Neovim-buffer plan/apply
suite on LuaJIT. `make test-lua51
LUA=lua5.1` runs the Lua 5.1-compatible subset, including `tests/polar.lua`.
`make test-remote` starts the WebSocket gateway and executes a cell with a real
client. `make test-webapp` runs the Node unit tests for the browser scene
renderer and its notebook model; it needs only Node, no npm packages. CI runs
these suites; graphics, input, and display-dependent visual smokes are manual
unless the workflow provides Xvfb and LÖVR.

## Visual smoke

```sh
./scripts/visual-smoke.sh       # coarse live-window check
./scripts/visual-baseline.sh    # pixel baselines from the offscreen canvas
./scripts/visual-baseline.sh --update
./scripts/polar-qa.sh           # live polar capture and blank check
./scripts/scene-qa.sh           # headless Chromium scene-pixel check
```

`visual-baseline.sh` renders the notebook through an offscreen rgba8 canvas,
reads it back from the GPU, and compares 50%-scale PNGs for cells 4, 6, and 7.
It is display-dependent and not part of `make test`.

`polar-qa.sh` builds a one-cell notebook with polar series, a 96x96 sampled
heatmap, contour isolines, a colourbar, a decimated quiver field, and two
integrated streamlines, checks the live/export block, arrow, and streamline
counts, runs it in the app, and writes `polar-live.png` under a scratch
directory (default `/tmp/luanb-polar-qa.*`).
It checks that the offscreen capture is non-blank and is useful for reviewing
the live circular frame, ticks, bar wedges, field cells, quiver glyphs,
streamline paths and heads, and colourbar without committing generated media.

`scene-qa.sh` (also `make qa-webapp`) serves `webapp/` with the bundled Lua
server, renders the browser fixture matrix in headless Chromium, and reads back
Canvas pixels for every scene type. It fails on a blank frame or a missing
series colour and keeps its DOM and logs under a scratch directory.

The offscreen canvas is also what makes screenshots independent of the
compositor and window stacking.

## LuaRocks

```sh
luarocks make lua-notebooks-1.59.0-1.rockspec
lua-notebooks
```

The rockspec installs the app source under the LuaRocks share tree and a
`lua-notebooks` launcher under its bin directory.

```sh
make rock
luarocks install lua-notebooks-1.59.0-1.src.rock
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
LUANB_SMOKE_POLAR=1 lovr . # run the polar scene cell, draw it, then quit
LUANB_SMOKE_GRID=1 lovr .   # run the grid extension cell, then quit
LUANB_SMOKE_WIDGET=1 lovr . # run the widget cell, then quit
LUANB_SMOKE_WIDGET_EVENT=1 lovr . # run the widget cell and change a slider
LUANB_SMOKE_SAVE=1 lovr .   # save/load the active notebook, then quit
LUANB_SMOKE_STATS=1 lovr .  # open/close notebook statistics, then quit
LUANB_SMOKE_GLOBAL_FIND=1 lovr . # search/jump across tabs, then quit
LUANB_SMOKE_CLOSE=1 lovr . # guard, close, and re-key notebook kernels, then quit
LUANB_SMOKE_OUTPUT=1 lovr . # expand a 12-line output, then quit
LUANB_SMOKE_WORKFLOW=1 lovr . # shortcuts, task click, tags/outline, restart + run below
LUANB_QA_CELL=6 lovr .      # run one cell and keep the window open for visual QA
LUANB_QA_TAGS=1 LUANB_QA_SCREENSHOT=1 lovr . # tag-index overlay screenshot
LUANB_QA_STATS=1 LUANB_QA_SCREENSHOT=1 lovr . # statistics overlay screenshot
LUANB_QA_OUTPUT=expanded LUANB_QA_SCREENSHOT=1 lovr . # expanded-output screenshot
LUANB_QA_TIMING=1 LUANB_QA_CELL=6 LUANB_QA_SCREENSHOT=1 lovr . # timing label
LUANB_QA_NVIM_DELETE=1 lovr . # confirm an omitted Neovim marker deletes safely
LUANB_QA_NVIM_DELETE=1 LUANB_QA_NVIM_DELETE_HOLD=1 LUANB_QA_SCREENSHOT=1 lovr . # deletion-prompt screenshot
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

## Neovim editor

The app embeds a headless Neovim instance and renders its `ext_linegrid` UI in
LÖVR. Press **Alt+E** or use the command palette action **Neovim cell editor**.

- `F10` writes the buffer back to the current cell;
- `F9` discards and closes;
- the editor starts in insert mode;
- `Escape` enters Vim normal mode for full Vim keybindings;
- in the notebook-wide buffer, a save that omits a `-- %% cell N` marker
  pauses and asks before deleting that cell. The confirmation lists each
  omitted cell with a preview of its first non-empty line. `Enter`/`y` deletes
  the omitted cell(s) as one undoable change; `Esc`/`n` cancels and keeps the
  buffer.

Requirements: `nvim` on `PATH`. The bridge uses msgpack-RPC over a local TCP
socket, not `luv` or `lua-mp`.

## Search and replace

Press **Ctrl+F** to search every cell. Results are case-insensitive and literal
by default; **Alt+C** toggles case-sensitive matching and **Alt+W** requires a
whole word (`foo` matches `foo` but not `food` or `foo_bar`). **Alt+K** cycles
the cell-kind filter through all, code, and Markdown cells. The overlay shows
the total occurrence count plus the visible row range; Up/Down select,
PageUp/PageDown page, and Home/End jump to the ends. Enter or a click selects
the matching cell and cursor position. Press **Alt+L** to limit the search to
the selected cell; the header shows `current cell` and result rows keep their
real notebook cell numbers.

**Ctrl+Shift+F** searches every open notebook at once. The overlay groups each
result by notebook title and cell number, shows the total occurrence count
across tabs, and supports the same **Alt+C**/**Alt+W**/**Alt+K** options.
Up/Down select, PageUp/PageDown page, and Home/End jump to the ends; Enter or a
click switches to the owning tab, selects the cell, restores the match cursor,
and scrolls it into view. The command palette exposes the same action as
**Search all open notebooks**.

**Ctrl+H** opens notebook-wide replace. It uses the same **Alt+C**/**Alt+W**
options, previews the number of replacements before applying, and replaces
every matching source occurrence as one undoable change. Press **Alt+L** to
replace only in the selected cell; the count and status use the same scope.
Output text is searchable but is never rewritten.

Press **Alt+R** in find, cross-notebook search, or replace to switch from
literal matching to **Lua patterns**. Use `%d+` for a digit run, `%a+` for
letters, and `%1`–`%9` in the replacement to expand captures (`%0` is the whole
match and `%%` is a literal percent). A malformed pattern is reported in the
overlay instead of breaking search. Zero-length pattern matches are skipped.
Ignore-case matching lowercases both the pattern and the searched text, so
capture text from an ignore-case replacement is lowercase.

## Kernel commands

The command palette exposes **Restart current kernel**, **Restart kernel and
run all cells**, **Clear all cell outputs**, **Run all code cells**, **Copy
selected cell source**, **Move selected cell up/down**, **Previous/next
heading**, **Collapse/expand all headings**, **Duplicate selected cell**,
**Close current notebook tab**, **Export notebook as Markdown**, and **Export
notebook as HTML**. `Ctrl+Shift+K` restarts the current kernel;
`Ctrl+Shift+F5` restarts and immediately runs every code cell, so the first
cell already sees a fresh global state. `Ctrl+W` closes the current tab; when
the notebook has unsaved changes, the prompt offers **Enter/Y** to discard,
**S** to save and close, or **Escape/N** to cancel. Kernels are keyed by
notebook, not tab number, so closing one tab keeps every remaining kernel and
its globals alive.

## Notebook workflow shortcuts

`Ctrl+Shift+C` copies the selected cell's source exactly, including Markdown
cells, without writing to the notebook or dirtying it. `Ctrl+Alt+C` copies the
cell's captured text output, or its error text; scene and widget state are not
clipboard text. `Ctrl+Alt+Enter` runs the selected cell and every code cell
below it, leaving earlier outputs untouched; `Ctrl+Alt+Up` runs from the first
code cell through the selected cell in source order. `Ctrl+V` pastes the
clipboard at the caret as one undoable edit. `Ctrl+Alt+X` clears the selected
cell's output, scene, widgets, and error (refusing while it is running), and
`Ctrl+Alt+T` reopens the most recently closed tab with a fresh kernel.
`Ctrl+Alt+W` closes every other tab that has no unsaved changes and reports how
many dirty tabs it kept. `Ctrl+Alt+S` saves every dirty tab and `Ctrl+Alt+K`
restarts every kernel. `Ctrl+Alt+G` opens a numeric **Go to cell** prompt;
Enter jumps and Esc cancels. `Alt+D` duplicates the selected cell.
**Shift+Enter** runs and selects the next cell, **Alt+Enter** runs and inserts a
new code cell below, and **Ctrl+Alt+R** clears the current output and reruns the
cell. The command palette adds **Restart kernel and clear outputs** and **Stop
run-all queue**; stopping cancels the queued cells while an already-running cell
may still finish.
**Alt+Up** and **Alt+Down** reorder
the selected cell in one step; the cell keeps its source, output, and widget
state. **Ctrl+Shift+Up** and **Ctrl+Shift+Down** jump to the nearest Markdown
heading before or after the selected cell without wrapping. The command palette
adds **Collapse all headings** and **Expand all headings**, which change every
heading as one undoable edit while leaving code cells alone.

## Line editing

`Ctrl+/` toggles a `--` comment on the current code line (Markdown cells are
left alone), `Alt+Shift+Up` and `Alt+Shift+Down` swap the line with its
neighbor, `Ctrl+Shift+D` duplicates it, and `Ctrl+]` / `Ctrl+[` indent or
outdent by two spaces (or one tab). `Ctrl+Left`/`Ctrl+Right` move by word,
`Ctrl+Backspace`/`Ctrl+Delete` delete a word, `Ctrl+Home`/`Ctrl+End` jump to the
cell bounds, and `Ctrl+J` joins the current line with the next. `Ctrl+Alt+L`
opens a numeric prompt and moves the caret to a line in the selected cell. Line
edits are normal undoable changes.

**F11** opens the heading outline with a type-to-filter field. Matching is a
case-insensitive substring over heading text, the header shows the visible page
and filtered count, and Up/Down move the highlight; PageUp/PageDown page and
Home/End jump to the ends. Enter or a click jumps to that heading and closes
the outline.

## Interactive task lists

In the live Markdown preview, clicking the `[x]` or `[ ]` marker of a task-list
item toggles that item in the cell source as one undoable edit. The rest of the
line, indentation, and list marker are preserved. The browser front-end also
renders those task checkboxes as live controls and saves the toggled source;
the static HTML export remains read-only with disabled checkboxes.

## Nested blockquotes

Consecutive Markdown quote lines retain their nesting depth. The live preview
indents deeper quotes with `│`, while the static export and browser front-end
emit nested `<blockquote>` elements; depth-one quotes keep the existing
one-paragraph-per-line layout.

## Callouts

A blockquote starting with `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`,
or `[!CAUTION]` becomes a callout. The title is normalized (`[!WARNING]` renders
as **Warning**), the remaining quoted lines keep their normal inline formatting,
and unknown types stay ordinary blockquotes. The live preview marks the title
with `▌`; the static export and browser emit
`<div class="callout callout-warning">` with matching title/body styles.

## Definition lists

A term line followed by a `: definition` line becomes a definition list. The
static export and browser emit `<dl>` with `<dt>`/`<dd>` pairs; the live preview
shows the definition indented after an em dash. Consecutive term/definition
pairs share one list, and a blank line starts normal content again.

## Links

Wiki links such as `[[Notebook Title]]` are previewed without brackets. Click a
rendered wiki link in the preview to switch to that notebook tab. The command palette lists other tabs as **Switch to** entries and marks tabs that link to the current notebook as **Backlink**. Press **F1** to open it; recently used commands float to the top, and PgUp/PgDn plus Home/End page through long lists.

The Neovim process is kept warm after F10/F9/F5, so reopening a cell or switching with Alt+J/K does not pay startup cost again. The process is destroyed when the app quits.

## Tags

Markdown `#tags` are indexed across open notebooks in the command palette; selecting one opens notebook-wide search for that tag. Press **Ctrl+T** for a tag-index overlay that shows every tag with its total use count and a clickable chip for each notebook that contains it, including that notebook's per-tag count (up to three chips, then `+N more`). The overlay has a type-to-filter field; matching is a case-insensitive substring over tag names, Up/Down move the highlight, PageUp/PageDown page through longer lists, Home/End jump to the ends, and Enter opens the selected tag. Click a chip to jump straight to that notebook and search for `#tag`, or click the tag row to use the current notebook when it has the tag and the first matching notebook otherwise; `Esc` closes the overlay.

Tag scanning only reads Markdown prose. Tags inside fenced code blocks, inline code spans, URL fragments, and hex colors such as `#fff`, `#cafe`, or `#1a2b3c` are ignored; tags in headings, lists, and parentheses are counted.

## Execution timing

Every code-cell run records its kernel execution time. The timing stays hidden by default, so the cell layout and committed visual baselines do not change; press **Ctrl+Shift+E** or choose **Toggle execution timing** in the command palette to show a compact duration next to the cell index. Timings are live session data and are not persisted in `.luanb` files. The status bar always reports the duration of the run that just finished, and **Expand all long outputs** / **Collapse all long outputs** in the palette change every output longer than six lines as one undoable edit. **Run all code cells** ends with the summed timed duration (for example, `all code cells finished in 1.24 s (6 timed)`).

Neovim completion uses external popupmenu events rendered over the grid. Held Backspace, Delete, arrow, Home/End, and PageUp/PageDown keys repeat. F10 applies changes to the notebook model; F6 writes the `.luanb` file.

## Long output

Text output is capped at six visible lines by default. A cell with more than
six lines gets a compact header showing the total line count and a **show all**
control; click the header or press **Ctrl+Shift+O** (or use **Toggle long cell
output** in the command palette) to expand it in place. The `output_expanded`
flag is stored per cell in the `.luanb` file, so a deliberately expanded log
survives save/load; short output never grows a header.

## Notebook statistics

Press **Ctrl+Shift+I** or choose **Notebook statistics** in the command palette
for a read-only overview of the active notebook: cell counts, source lines split
by kind, prose words, headings, wiki links, tags, text outputs, figures,
widgets, errors, timed execution total, and kernel name. The overlay is a
snapshot taken when it opens; `Esc`, **Ctrl+Shift+I**, or a click closes it. It
does not change the notebook or any cell layout.

## Autosave and recovery

While a notebook is dirty, the app writes a crash-recovery copy every 20 seconds under the app save directory (`autosaves/`). The command palette action **Recover autosaved notebook** opens that copy as a new tab. A successful F6 save removes the recovery copy.

## Session restore

Notebook paths opened during a session are recorded in `session.json`. On the next launch, they are reopened automatically unless command-line paths were supplied. Use the command palette action **Clear restored session** to forget them.

## Recent notebooks

Successfully opened paths are kept in `recent.json` (latest ten). They appear as **Recent:** entries in the command palette; **Clear recent notebooks** removes them.

## HTML export

Exports are self-contained HTML with no external assets. The document has viewport and description metadata, a dark-mode-aware stylesheet, a print stylesheet, a sticky table of contents with unique heading anchors, per-heading and per-cell permalinks, a figures section, styled outputs and errors, and a closing backlinks list computed from `[[wiki links]]` across the open notebooks. Code cells and fenced Markdown blocks render with a language badge, CSS line numbers, and a **Copy** button that copies the source without the numbers; without JavaScript the button is hidden and every block stays readable. Markdown thematic breaks render as rules, `~~text~~` renders as strikethrough, `==text==` renders as `<mark>`, bare `http(s)://` URLs become links, backslash-escaped punctuation stays literal, and ordered lists keep their first number in the generated `<ol start="…">`. Pipe tables become `<table class="markdown-table">` with `align-left`/`align-center`/`align-right` cells, nested lists keep their hierarchy, italic emphasis renders as `<em>`, and consecutive blockquote lines share one `<blockquote>`.

A small inline script adds reader-facing full-text search and a cell-kind filter. Search is case-insensitive, whitespace-separated terms are combined with AND, `/` focuses the box, Escape clears it, and the table of contents hides links to filtered-out cells. `?q=term` and `?kind=figures` prefill the controls for shareable filtered links. Without JavaScript the controls are hidden and the full document remains readable.

Code-cell scene outputs become `<figure>` placeholders with a deterministic inline SVG preview (Cartesian line, scatter, bar, and histogram; polar line, scatter, bar, heatmap, contour, quiver, and streamplot; plus `cube` and `grid`), a caption with series/point counts, and a collapsible JSON scene dump. Polar previews honour zero/direction/`rmax`, the supplied theta/r ticks, quiver scale/pivot/normalization and arrow decimation, and streamplot step/periodicity/cap metadata. The live viewport renders the same polar IR; both backends use `notebook/polar.lua` for rmax resolution, projection, tick fallbacks, sampling caps, label limits, bar wedges, heatmap/contour geometry, quiver arrows, and streamplot polylines and heads. Interactive widgets are listed but not exported. The static preview is a sketch of the scene, not a raster of the live renderer. See [docs/export.md](docs/export.md) for the document shape, search semantics, Markdown subset, safety rules, and determinism guarantees.

From a source checkout, `luajit tools/export.lua INPUT.luanb OUTPUT.html` exports without opening the app (use `-` for stdout and extra `.luanb` arguments for backlinks). `./scripts/export-qa.sh` builds a fixture, verifies `?q=`/`?kind=` filtering plus task lists, definition lists, rules, strikethrough, ordered-list starts, heading permalinks, and copy controls in headless Chromium, and captures light/dark/narrow screenshots under `/tmp`. `./scripts/polar-qa.sh` does the corresponding live app check for a polar scene.

## Link graph

Press **Ctrl+G** for an overlay of the current notebook’s outgoing `[[wiki links]]` and incoming backlinks. Click a title to open it, or Esc to close.
