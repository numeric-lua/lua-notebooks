# Shader widgets

Kernels can request a live shader preview:

```lua
widgets.shader({ label = "Star Nest", shader = "star_nest", height = 180 })
```

The host compiles the fragment shader once, sends a `time` uniform, and clips it
to the widget rectangle. `shader` can be a preset name or inline fragment source
using LÖVR shader syntax.

## Browser preview

The web front-end (`webapp/js/shader.js`) renders the built-in `star_nest`
preset locally in a WebGL canvas with a `time` uniform. It does not receive
graphics handles from the kernel: widgets stay plain serializable specs, and
the browser preview is entirely host-side.

Browser support is intentionally limited to that preset. Inline LÖVR shader
source and unknown preset names show a fallback message instead of throwing,
and WebGL failures degrade to the same message. Use the LÖVR desktop host for
custom shaders and additional presets.

## Star Nest

The included `star_nest` preset is adapted from **Star Nest** by Pablo Román
Andrioli, via the `shooter` project:

```text
Star Nest by Pablo Román Andrioli
Copyright (c) Pablo Román Andrioli
MIT License
```

The original shader is published under the MIT License. The adapted source keeps
the same attribution and is included in `ui/shader.lua` for the desktop host and
`webapp/js/shader.js` for the browser preview.

## DejaVu Sans

The math font files are DejaVu Sans regular, bold, and oblique. Their license is
included in `assets/DEJAVU-LICENSE.txt`.
