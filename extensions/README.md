# Extensions

Planned extension surface:

```lua
local surface = notebook.new_surface(width, height)
surface:draw(pass, scene)
surface:pointer(x, y, pressed)
```

The host creates a `Pass` with a render-target `Texture`, lets the extension
draw into it, then composites it into the cell. The kernel never receives the
Pass or any graphics object.

Until that lands, `cell.scene = "cube"` is a hardcoded host-side demo. Do not
add arbitrary kernel graphics calls as a shortcut.


## Implemented registry

`extensions/init.lua` exposes:

```lua
Extensions.register(name, { render = function(pass, time, w, h) ... end })
Extensions.get(name)
```

Each surface has its own `Texture` and `Pass`, sized to the cell and recreated
when the cell resizes. `ui/surface.lua` clears and records the pass, composites
the texture into the window pass, and submits extension passes before the
window pass.

The built-in `cube` extension is in `extensions/cube.lua`. It is a deliberate
minimal example of the same contract external extensions will use.
