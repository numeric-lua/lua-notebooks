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
