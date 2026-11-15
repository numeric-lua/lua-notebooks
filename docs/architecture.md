# Architecture

## 1. Host and kernels

The LÖVR main thread is the **host**. It owns the window, graphics, input, and
notebook UI. Each notebook owns a persistent **kernel thread** with its own Lua
state and a pair of named channels.

```text
main thread                         kernel thread
-----------                         -------------
UI.draw(pass)                       execute cell
  │                                   ├── capture print/io.write
  ├── Channel:push({code}) ────────▶  ├── loadstring/xpcall
  │                                   └── Channel:push(result)
  └── Channel:pop() ◀─────────────────┘
```

Kernel threads cannot call `lovr.graphics`. They return:
- captured text output,
- an error string,
- an optional scene description.

This is a deliberate boundary. It lets the host remain responsive and gives a
future process-isolated kernel the same protocol.

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

The in-memory model is `notebook/model.lua`. Load/save through
`lovr.filesystem` is the next step; LÖVR only permits writes in its save
directory, so the UI must make that location visible.

## 3. Extension surfaces

The extension model is **one scene surface per extension**, not arbitrary
kernel graphics access.

- Each extension gets a `Pass` with one or more render-target `Texture`s.
- The extension renderer records draws into that pass.
- The notebook composites the texture into the cell viewport (the native
  equivalent of an iframe).
- The kernel may send commands/events to the extension over a protocol; it does
  not own the Pass.

The first milestone uses a single host viewport for the cube, so the render
target path is intentionally not on the critical path yet. The next milestone
should add:

1. `Pass`/texture per extension surface,
2. resizing the surface with the cell,
3. pointer events forwarded to the extension,
4. a hot-reload boundary that reloads the renderer without reloading the
   kernel.

`lovr-ent` uses entity-app surfaces; `lite-lovr` uses a host/thread draw-command
protocol. Both point to the same separation.

## 4. luaplotlib backend

luaplotlib currently renders SVG. The LÖVR backend should consume a **scene
IR**, not SVG strings:

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

Then:
- the host converts IR to meshes/buffers and draws through a Pass;
- the kernel can return the IR;
- a future static/PNG backend can consume the same IR.

Do not make luaplotlib depend on LÖVR. The adapter belongs in a separate module
or repository.

## 5. Kernel isolation roadmap

Today: LÖVR threads (separate Lua states, shared process). Good for state
isolation, low overhead, and crash containment at the Lua level.

Next: OS-process kernels with a pipe/socket protocol. That gives memory limits,
crash containment at the process level, and the ability to run kernels without a
graphics context. The channel message schema is the compatibility boundary.

## 6. Startup and resource goals

- Host startup target: under one second to first notebook frame.
- Kernel target: a few MB and no GPU context per kernel.
- Many notebooks: bounded by LÖVR worker threads today; process kernels later.
- Never run a kernel in the host's graphics thread.
