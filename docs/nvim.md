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
- `F9` discard;
- pure tests for codec, grid, RPC, and session.

Known gaps:

- mouse input;
- font advance and cursor alignment are approximate;
- no light colorscheme selection yet;
- resize is disabled in the overlay to avoid clearing the grid;
- Windows transport is not implemented;
- no inline extmarks, popup menu, command-line completion overlay.
