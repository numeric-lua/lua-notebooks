# Shader widgets

Kernels can request a live shader preview:

```lua
widgets.shader({ label = "Star Nest", shader = "star_nest", height = 180 })
```

The host compiles the fragment shader once, sends a `time` uniform, and clips it
to the widget rectangle. `shader` can be a preset name or inline fragment source
using LÖVR shader syntax.

## Star Nest

The included `star_nest` preset is adapted from **Star Nest** by Pablo Román
Andrioli, via the `shooter` project:

```text
Star Nest by Pablo Román Andrioli
Copyright (c) Pablo Román Andrioli
MIT License
```

The original shader is published under the MIT License. The adapted source keeps
the same attribution and is included in `ui/shader.lua`.

## DejaVu Sans

The math font files are DejaVu Sans regular, bold, and oblique. Their license is
included in `assets/DEJAVU-LICENSE.txt`.
