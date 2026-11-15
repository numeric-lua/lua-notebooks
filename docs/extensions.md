# Extensions

An extension is a Lua module in `extensions/` that returns a descriptor:

```lua
local MyExtension = {
  id = "my-ext",          -- ^[a-z][a-z0-9_-]*$, unique
  version = 1,
  title = "My extension",
  render = function(pass, time, width, height, state) end,
  pointer = function(state, event) end,  -- optional
  key = function(state, event) end,      -- optional
  text = function(state, value) end,     -- optional
  resize = function(state, width, height) end, -- optional
}

return MyExtension
```

## Host contract

- The host creates one `Texture` and `Pass` per scene cell.
- `render` receives only its offscreen pass. It must not draw to the window.
- `state` is owned by the surface and survives renderer reloads.
- The host composites the texture into the notebook and submits extension
  passes before the window pass.
- Pointer events are delivered only while the surface is under the pointer:
  - `down`, `move`, `up`: local `x`, `y`, plus `dx`, `dy`.
  - `wheel`: `dy`.
- Key events go to the focused surface. F5–F8 remain global notebook commands.
- Text input goes to the focused surface if it implements `text`.
- `resize` is called when the cell size changes.

## Discovery and reload

`extensions/loader.lua` discovers `*.lua` modules, validates them through
`extensions/manifest.lua`, and registers them by id. `init.lua`, `loader.lua`,
and `manifest.lua` are internal and skipped.

The notebook calls `Extensions.discover()` at startup. F8 reloads the focused
extension. `lovr.filesystem.watch()` is enabled and `lovr.filechanged` reloads
the changed extension module without restarting the notebook or its kernel.

A malformed module is reported in `Extensions.errors`; the old renderer remains
usable.

## Built-ins

- `extensions/cube.lua`: orbit/zoom demo.
- `extensions/grid.lua`: grid demo; Space toggles density.

## Not yet

- External installation/permissions.
- A generic widget protocol (sliders/buttons) is the next layer.
- Hot reload of kernel code; only renderers reload.
