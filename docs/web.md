# Web export

LÖVR supports an Emscripten/WASM build. The browser cannot run LuaJIT, so LÖVR
uses the bundled **PUC Lua 5.1** interpreter for the web build. Threads are also
disabled under Emscripten.

lua-notebooks targets that runtime in two ways:

1. the kernel engine is Lua 5.1-compatible and has no `ffi` dependency
   (`kernel/engine.lua`);
2. `notebook/runtime.lua` detects `lovr.system.getOS() == "Web"` and selects
   `notebook/inline_supervisor.lua`, which runs cells on the host thread.

## Browser front-end without LÖVR

The supported browser path is [`webapp/`](../webapp/): static HTML/ES modules
that use the native WebSocket and Canvas APIs. It needs no Emscripten or
COOP/COEP headers. Start the gateway and serve the directory:

```sh
python3 -m http.server 8010 --directory webapp
```

Then open <http://127.0.0.1:8010/>. See [webapp/README.md](../webapp/README.md).
The LÖVR web instructions below are retained for the eventual upstream
graphics fix and for the validated transport bridge.

## Build LÖVR for the web

Follow the [LÖVR web build guide](https://lovr.org/docs/v0.19.0/Compiling).
In short, with `emsdk` active:

```sh
git clone https://github.com/bjornbytes/lovr.git
cd lovr
git submodule update --init --recursive
git clone https://github.com/bjornbytes/tincture deps/tincture
emcmake cmake -B build -DLOVR_PROJECT=/absolute/path/to/lua-notebooks
cmake --build build
```

Serve `build/` over HTTP and open `lovr.html` in a browser. The build emits
`lovr.wasm`, `lovr.js`, `lovr.html`, and `nogame.lovr`. Use
`web/serve.py` so the COOP/COEP headers required by the threaded/JSPI runtime
are present.

## Runtime behavior

| capability | desktop | web |
| --- | --- | --- |
| Lua runtime | LuaJIT (5.1) | PUC Lua 5.1 |
| kernels | one thread per notebook | inline, one job per frame |
| remote kernel | WebSocket/native client | browser bridge in `web/` |
| `ffi` / process kernels | available | unavailable locally; available on remote kernel |
| external LSP worker | available | disabled |
| bubblewrap extension sandbox | available | unavailable |
| notebook/scene/widgets | available | available |

`notebook/inline_supervisor.lua` queues jobs and executes one per `poll()`, so
long cells can still stall a frame; cooperative yielding is future work.

## Remote kernel bridge

For the Jupyter-style deployment, the browser can act as a front-end for a
remote LuaJIT kernel instead of running the inline engine. The Emscripten
bridge lives in `web/` and is installed into a LÖVR checkout:

```sh
./web/install-bridge.sh /path/to/lovr
```

It exposes a nonblocking `lovr_websocket` module to Lua 5.1, and
`notebook/browser_transport.lua` adapts it to `RemoteSupervisor`. Put the
gateway URL in `remote.txt`:

```text
ws://127.0.0.1:8765
```

Use `wss://` and authentication for anything beyond localhost. See
[web/README.md](../web/README.md) and [remote.md](remote.md) for the build and
server details.

The bridge was built into LÖVR v0.19.1 with Emscripten 5.0.2 and exercised from
headless Firefox and Chromium against the gateway, including a returned cell
result and a second cell. Emscripten 4.0.23 gets past the original graphics
crash but Chromium rejects LÖVR's text pipeline; both are upstream LÖVR/WebGPU
issues, not notebook-transport issues.

## Verification

The pure tests are Lua 5.1-compatible:

```sh
make test-lua51 LUA=lua5.1
```

CI runs the same target with the distribution's `lua5.1` package. A real browser
smoke test still needs a machine with `emsdk` and a headless browser; it is not
part of the current CI.
