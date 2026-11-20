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
- notebook-wide code buffer with `-- %% cell N` markers;
- `F5` runs the cell containing the cursor from that buffer;
- pure tests for codec, grid, RPC, and session.

Known gaps:

- font advance and cursor alignment are approximate;
- no external `ext_cmdline`/`ext_messages` overlay;
- Windows uses TCP transport;
- marker add/delete is rejected; reordering is supported;
- the headless process uses `--clean`, so user Neovim plugins are not loaded.
