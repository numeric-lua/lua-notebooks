# Neovim editor spike

The editor is a real Neovim process, not a Vim emulation layer.

## Components

- `notebook/nvim/msgpack.lua` — pure Lua MessagePack codec.
- `notebook/nvim/rpc.lua` — LuaJIT FFI Unix/TCP transport.
- `notebook/nvim/grid.lua` — `ext_linegrid` screen model.
- `notebook/nvim/session.lua` — headless nvim spawn, attach, resize, close.
- `ui/nvim.lua` — LÖVR grid renderer and input adapter.
- `nvim_demo.lua` — standalone renderer demo.

## Status

Working:

- spawn `nvim --headless --listen`;
- msgpack-RPC request/notification handling;
- UI attach, grid lines, highlights, cursor, default colors;
- cell source loaded into a temp buffer;
- per-cell Neovim editing with the notebook rendering the text itself;
- the cell buffer is synchronized live; only the cursor is overlaid;
- cells open in Neovim normal mode; `i`/`a` enter insert;
- block cursor in normal/visual mode, bar cursor in insert;
- `Esc` returns from normal mode to notebook navigation;
- inline font, background, and syntax colors are the notebook's own;
- insert-mode typing and `F10` write-back;
- `F5` writes and runs the cell;
- `F9` discard;
- `Alt+E` opens, `Alt+J/K` saves and moves to the next/previous cell;
- mouse clicks and wheel scrolling;
- external popupmenu completion rendered over the grid;
- held special-key repeat;
- markdown cell buffers;
- light/dark background and colorscheme;
- live grid resize;
- warm Neovim process reused across cells;
- private Unix socket with a 0700 directory and server handshake;
- optional full-screen notebook-wide buffer with `-- %% cell N` markers;
- `F5` runs the cell containing the cursor from that buffer;
- omitted markers pause the save for explicit deletion confirmation instead of
  silently dropping cells;
- pure tests for codec, plan/apply marker reconciliation, grid, RPC, and
  session.

Known gaps:

- font advance and cursor alignment are approximate;
- no external `ext_cmdline`/`ext_messages` overlay;
- Windows uses TCP transport;
- new marker blocks create cells; deleting markers requires explicit
  `Enter`/`y` confirmation (`Esc`/`n` keeps the buffer) and is undoable;
  reordering is supported;
- the headless process uses `--clean`, so user Neovim plugins are not loaded.
