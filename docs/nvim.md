# Neovim editor spike

The editor is a real Neovim process, not a Vim emulation layer.

## Components

- `notebook/nvim/msgpack.lua` — pure Lua MessagePack codec.
- `notebook/nvim/rpc.lua` — LuaJIT FFI TCP transport.
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
- insert-mode typing and `F10` write-back;
- `F5` writes and runs the cell;
- `F9` discard;
- `Alt+E` opens, `Alt+J/K` saves and moves to the next/previous cell;
- mouse clicks and wheel scrolling;
- grid-rendered completion (external popup events disabled until polished);
- markdown cell buffers;
- light/dark background and colorscheme;
- live grid resize;
- notebook-wide code buffer with `-- %% cell N` markers;
- `F5` runs the cell containing the cursor from that buffer;
- pure tests for codec, grid, RPC, and session.

Known gaps:

- font advance and cursor alignment are approximate;
- no external `ext_cmdline`/`ext_messages` overlay;
- popup completion depends on Neovim emitting popup events;
- Windows transport is not implemented;
- the headless process uses `--clean`, so user Neovim plugins are not loaded.
