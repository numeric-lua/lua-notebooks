# Remote kernels

lua-notebooks can act as a front-end for a LuaJIT kernel running elsewhere, in
the same way JupyterLab fronts a remote Python kernel.

## Status

Implemented:

- `notebook/remote_supervisor.lua`, a transport-agnostic supervisor with the
  same `open`/`run`/`widget`/`poll` surface as the local supervisors;
- a dependency-free WebSocket gateway (`scripts/kernel-gateway.lua`);
- a native WebSocket client for desktop LÖVR;
- optional desktop remote mode;
- a browser Emscripten bridge in `web/lovr_websocket.c`, installed with
  `web/install-bridge.sh`;
- an end-to-end gateway smoke test (`make test-remote`).

The bridge was linked into LÖVR v0.19.1 with Emscripten 5.0.2 and validated from
headless Firefox with a no-graphics smoke project: the browser connected, ran a
`40 + 2` cell, received the result, and sent a second `99` cell. Full notebook
rendering still requires a WebGPU-capable browser.

On desktop, the LÖVR host itself can use the gateway:

```sh
LUANB_KERNEL_MODE=remote LUANB_REMOTE_URL=ws://127.0.0.1:8765 lovr .
```

A failed connection falls back to the normal desktop thread/inline path.

## Architecture

```text
front-end (LÖVR web, native client, test)
  └── RemoteSupervisor
          │ JSON text messages over WebSocket
          ▼
scripts/kernel-gateway.lua
  ├── WebSocket handshake/framing
  ├── one sequential connection (prototype)
  └── kernel/engine.lua
          └── full LuaJIT + FFI libraries on LUA_PATH/LUA_CPATH
```

The gateway binds to `127.0.0.1` by default. It is not an authenticated or
sandboxed public service.

## Run the gateway

```sh
LUA_PATH="$PWD/?.lua;$PWD/?/init.lua;;" \
  luajit scripts/kernel-gateway.lua --host 127.0.0.1 --port 8765
```

It prints:

```text
GATEWAY_READY ws://127.0.0.1:8765
```

Any WebSocket client can then use the protocol.

To make luatorch, tensorflow-lua, numlua, or lua-polars available to cells,
start the gateway with the same `LUA_PATH`, `LUA_CPATH`, and native-library
environment used by a desktop lua-notebooks session.

## Protocol

Client → gateway:

```json
{"type":"open","notebook":"nb1"}
{"type":"run","notebook":"nb1","id":1,"cell":"1:1","code":"return 6*7"}
{"type":"widget","notebook":"nb1","id":2,"cell":"1:1","widget":"w1","event":{"type":"click"}}
{"type":"restart","notebook":"nb1"}
{"type":"close","notebook":"nb1"}
```

Gateway → client:

```json
{"type":"hello","capabilities":{"runtime":"luajit","ffi":true}}
{"type":"open_ok","notebook":"nb1"}
{"type":"result","id":1,"ok":true,"output":"","value":"42","scene":null,"widgets":[]}
{"type":"error","id":1,"message":"..."}
```

The `result` payload is the same shape returned by the local kernel engine.

## Front-end transport contract

`RemoteSupervisor.new` takes a transport with:

```lua
transport.send(text)       -- send one JSON text frame
transport.receive()        -- return one JSON text frame or nil
transport.close()          -- optional
```

Callbacks match the local supervisors:

```lua
local remote = RemoteSupervisor.new({
  transport = transport,
  on_result = function(notebook_id, request, message) ... end,
  on_error = function(notebook_id, message) ... end,
})
```

## Browser bridge requirement

LÖVR’s web build uses Lua 5.1 and does not include `http` or a browser
WebSocket binding. A production browser front-end needs one of:

1. a small Emscripten C/Lua module exposing WebSocket frames to Lua;
2. a JavaScript bridge that exchanges JSON through the Emscripten filesystem;
3. a streaming/VNC-style front-end instead of a LÖVR web client.

The gateway and supervisor are deliberately independent of that choice.

## Security

A remote kernel executes arbitrary Lua. Before exposing it beyond localhost:

- require authentication and TLS;
- run one sandbox/container per session;
- enforce CPU, memory, wall-time, and output limits;
- mount datasets read-only;
- disable network access unless explicitly needed;
- never run the gateway as root;
- terminate idle kernels.
