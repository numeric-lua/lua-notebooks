# Architecture

## 1. Host and kernels

The LÖVR main thread is the **host**. It owns the window, graphics, input, and
notebook UI. On desktop each notebook owns a persistent **kernel thread** with
its own Lua state and a pair of named channels. On web, where LÖVR disables
threads, the same kernel engine runs inline through a queued supervisor.

```text
main thread                         kernel thread
-----------                         -------------
UI.draw(pass)                       execute cell
  │                                   ├── capture print/io.write
  ├── Channel:push({code}) ────────▶  ├── loadstring/xpcall
  │                                   └── Channel:push(result)
  └── Channel:pop() ◀─────────────────┘
```

Kernels cannot call `lovr.graphics`. They return:
- captured text output,
- an error string,
- an optional scene description.

This is a deliberate boundary. It lets the host remain responsive, keeps the
web path working without threads, and gives process-isolated kernels the same
protocol. The shared execution logic lives in `kernel/engine.lua`; desktop
threads and the web inline supervisor both call it. The engine uses `setfenv`
and `loadstring`, so it targets Lua 5.1 (LuaJIT and LÖVR’s web runtime).

## 2. Notebook document

A notebook is plain JSON:

```json
{
  "version": 1,
  "name": "welcome.luanb",
  "cells": [
    {"kind": "code", "source": "print('hi')", "output": "", "scene": null},
    {"kind": "markdown", "source": "# title"}
  ]
}
```

The in-memory model is `notebook/model.lua`; `notebook/format.lua` implements
JSON encode/decode and save/load through `lovr.filesystem`. F6/F7 save and load
the active notebook in the LÖVR save directory, which the status line reports.
Native file dialogs are still future work.

## 3. Extension surfaces

The extension model is **one scene surface per extension**, not arbitrary
kernel graphics access.

- Each extension gets a `Pass` with one or more render-target `Texture`s.
- The extension renderer records draws into that pass.
- The notebook composites the texture into the cell viewport (the native
  equivalent of an iframe).
- The kernel may send commands/events to the extension over a protocol; it does
  not own the Pass.

The extension registry and render-target path are now implemented:

1. each scene cell owns a `Texture` and a `Pass` (`ui/surface.lua`),
2. the surface is recreated when the cell resizes,
3. extension passes are submitted before the window pass, which composites the
   texture with `pass:draw(texture, ...)`,
4. `extensions/init.lua` exposes `register`/`get`; `extensions/cube.lua` is the
   first renderer.

Pointer orbit/zoom events and F8 hot reload of the built-in renderer are now
wired. Still missing: a general widget event protocol, external extension
loading/permissions, and process-separated kernels.

`lovr-ent` uses entity-app surfaces; `lite-lovr` uses a host/thread draw-command
protocol. Both point to the same separation.

## 4. luaplotlib backend

luaplotlib has a renderer-agnostic **scene IR** (`luaplotlib.scene` /
`figure:to_scene()`) in addition to its SVG renderer. The LÖVR backend consumes
that IR, not SVG strings:

```lua
{
  type = "plot3d",
  series = {
    { kind = "line", x = {...}, y = {...}, z = {...} },
    { kind = "points", x = {...}, y = {...}, z = {...} },
  },
  camera = { yaw = 0.7, pitch = 0.3, distance = 4 },
}
```

The notebook's `ui/plot.lua` currently implements the 2D line/scatter/bar/hist
part of this IR. It maps data coordinates into the cell viewport, draws axes and
ticks, and renders through the host pass. A future 3D backend can consume the
same IR; a kernel can return it without touching graphics.

Do not make luaplotlib depend on LÖVR. The adapter belongs in a separate module
or repository.

## 5. Widgets

Widgets are kernel-declared specs plus callbacks. `kernel/widgets.lua` owns the
values and callbacks; `ui/widgets.lua` draws them; `App:widget_event` sends an
event back to the same kernel. This is the same boundary as scenes: the kernel
returns data, the host owns interaction and rendering.

See [`docs/widgets.md`](docs/widgets.md).

## 6. Kernel isolation roadmap

Default: LÖVR threads (separate Lua states, shared process). Low overhead and
state isolation.

Experimental: a plain-LuaJIT child process per notebook, communicating through
atomically renamed JSON job/result files. The child has no graphics context; a
crash or `os.exit` only affects that child. The host polls results, times out
after 8 seconds, and restarts the child. See `docs/process-kernels.md`.

The message schema is shared between both backends.

## 7. Startup and resource goals

- Host startup target: under one second to first notebook frame.
- Kernel target: a few MB and no GPU context per kernel.
- Many notebooks: bounded by LÖVR worker threads today; process kernels later.
- Never run a kernel in the host's graphics thread.
