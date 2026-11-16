# LÖVR WebSocket bridge

This directory contains the C bridge that lets the LÖVR web build use a remote
lua-notebooks kernel. The browser owns the WebSocket; the module exposes a small
nonblocking event queue to Lua 5.1.

## Install into a LÖVR checkout

Use LÖVR 0.19.x and its Emscripten build:

```sh
git clone https://github.com/bjornbytes/lovr.git
cd lovr
git submodule update --init --recursive
git clone https://github.com/bjornbytes/tincture deps/tincture

/path/to/lua-notebooks/web/install-bridge.sh .
```

The installer:

- copies `lovr_websocket.c` and its header into `src/api/`;
- registers the module in `package.preload` before the project boots;
- adds the source and `-lwebsocket.js` to LÖVR's Emscripten target.

## Build the notebook project

From the LÖVR checkout, with `emsdk` active:

```sh
emcmake cmake -B build -DLOVR_PROJECT=/absolute/path/to/lua-notebooks
cmake --build build
python3 -m http.server -d build 8000
```

Open `http://localhost:8000` after setting the gateway URL. In the project
directory, either create `remote.txt` containing the URL, or set
`LUANB_REMOTE_URL` at build/runtime if the environment is available:

```sh
printf '%s\n' 'ws://127.0.0.1:8765' > /absolute/path/to/lua-notebooks/remote.txt
```

For a public deployment use `wss://` and put authentication and TLS at the
gateway. Do not expose the prototype gateway directly to the internet.

## Lua API

```lua
local ws = require("lovr_websocket")
ws.open("ws://127.0.0.1:8765")
ws.send("...")
local event = ws.poll()
-- nil | { type = "open" }
--     | { type = "message", data = "..." }
--     | { type = "close", code = 1000, message = "..." }
--     | { type = "error", message = "..." }
ws.state()  -- 0 connecting, 1 open, 2 closing, 3 closed
ws.close()
```

`notebook/browser_transport.lua` wraps this API for `RemoteSupervisor`; it
queues outbound messages until the socket reports `open`.

## Build assumptions

The bridge is compiled only for Emscripten. It uses the browser WebSocket
implementation supplied by Emscripten (`-lwebsocket.js`), so it inherits browser
TLS, origin, and proxy behavior. A desktop LÖVR build keeps using the native
WebSocket client (`notebook/websocket_transport.lua`).

The bridge has not yet been through a browser CI job in this repository; the
C module was syntax-checked against the Emscripten API but requires an `emsdk`
build to validate end to end.
