# Lua Notebooks · Web

A dependency-free browser front-end for the remote LuaJIT kernel. It uses
only the native browser WebSocket and Canvas APIs — no Emscripten, LÖVR,
threads, COOP/COEP, or build step.

## Run

Start the kernel gateway from the repository root:

```sh
LUA_PATH="$PWD/?.lua;$PWD/?/init.lua;;" \
  luajit scripts/kernel-gateway.lua --port 8765
```

Serve this directory:

```sh
python3 -m http.server 8010 --directory webapp
```

Open:

```text
http://127.0.0.1:8010/
```

The default WebSocket URL is `ws://127.0.0.1:8765`. Override it with:

```text
http://127.0.0.1:8010/?ws=ws://127.0.0.1:9000
```

or with the settings button in the top bar.

## What works

- code and markdown cells, local notebook persistence, `.luanb` import/export;
- Shift+Enter / Ctrl+Enter execution;
- stdout, returned values, errors;
- kernel widgets: sliders, buttons, checkboxes, selects, text, numbers,
  progress, labels;
- `luaplotlib` line, scatter, and bar scenes;
- `cube` and `grid` scene strings as local canvas drawings;
- run all, kernel restart, auto-reconnect.

## Deliberate limits

- shader widgets show a placeholder; the shader editor/renderer stays in the
  LÖVR desktop host;
- arbitrary LÖVR scene tables are not rendered, only `luaplotlib` and the
  built-in `cube`/`grid` strings;
- markdown math is displayed as styled source rather than typeset TeX;
- the gateway is a loopback development service with no authentication or
  sandboxing. Use TLS, authentication, and per-session isolation before
  exposing it.

## Architecture

```text
webapp/  (HTML + ES modules + Canvas)
    │  native WebSocket JSON
    ▼
scripts/kernel-gateway.lua
    └── kernel/engine.lua  (LuaJIT + FFI libraries)
```

The front-end speaks the same `open` / `run` / `widget` / `restart` protocol as
`RemoteSupervisor`, so the desktop LÖVR host and the browser share one kernel
contract.

## Tested

Validated in Chromium against a local gateway:

- notebook loaded and opened the kernel;
- `print(...); return 6*7` produced the captured output and `42`;
- widgets created and a button click returned `pong`;
- two scene canvases rendered (chart and cube);
- no page exceptions.
