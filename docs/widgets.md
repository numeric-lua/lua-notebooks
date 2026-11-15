# Widgets

Kernel-declared widgets are the Lua notebook analogue of ipywidgets. The
kernel owns values and callbacks; the host owns rendering and input.

## Kernel API

Inside a cell, the global `widgets` table provides:

```lua
local gain = widgets.slider({
  label = "gain",
  min = 0, max = 10, value = 3, step = 1,
  on_change = function(value)
    print("gain =", value)
  end,
})

widgets.button({
  label = "Ping",
  on_click = function() print("pong") end,
})

widgets.checkbox({ label = "enabled", value = true,
  on_change = function(value) print(value) end })

widgets.select({ label = "mode", options = { "fast", "slow" },
  value = "fast", on_change = function(value) print(value) end })

widgets.number({ label = "count", min = 0, max = 20, step = 1, value = 2 })
widgets.text({ label = "name", value = "notebook" })
widgets.progress({ label = "loading", min = 0, max = 1, value = 0.4 })
widgets.label({ text = "A plain label" })
```

Every constructor returns a spec table with an `id`. `widgets.set_value(spec, value)`
updates a value from the kernel.

## Protocol

Widgets are created while a cell job is executing and tagged with the cell
token (`<notebook>:<cell>`). When the cell finishes, the kernel returns:

```lua
{
  widgets = { { id = "w1", kind = "slider", ... }, ... },
  output = "captured print output",
  value = nil,
  scene = nil,
}
```

A host event is another kernel job:

```lua
{ cell = "1:6", widget = "w1", event = { type = "change", value = 7 } }
```

The kernel calls the stored callback, captures its output, and returns the
updated widget list. Host events currently include `change`, `click`, `toggle`,
and `next`.

## Host rendering

`ui/widgets.lua` renders sliders, buttons, checkboxes, selects, numbers, text
fields, progress bars, and labels. `ui/notebook.lua` handles hit testing and
routes changes to `App:widget_event`.

- The kernel does not receive graphics objects.
- Widget state is serialized in `.luanb` files (callbacks are not; they are
  recreated by running the cell).
- Widget IDs are kernel-scoped and change when the kernel restarts.
- Text widgets are editable on the host. Text is committed to the kernel on
  Enter and cancelled with Escape; `on_change` runs on commit.
- `widgets.text({ multiline = true })` supports wrapped source text and
  Shift+Enter newlines; Enter commits the whole value.
- `widgets.shader({ shader = "star_nest", height = 180 })` renders a live
  host-side shader into the cell. Named presets include the MIT-licensed
  Star Nest shader from the shooter project. Shader widgets have no kernel
  callback.
- Slider dragging updates the host immediately and sends the final value on
  mouse release.

## Security

Widget callbacks execute in the kernel, not the host. They can print, compute,
create more widgets, and return scene data. They cannot draw to the notebook.
