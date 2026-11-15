# Extensions

See [`docs/extensions.md`](../docs/extensions.md) for the manifest and event
contract.

Each extension owns a render-target surface (`Pass` + `Texture`), receives
local pointer/key events, and is loaded through `extensions/loader.lua`. The
built-in cube and grid are reference implementations.

The next layer is a widget protocol for sliders, buttons, checkboxes, selects,
and text inputs, with events routed back to the kernel.
