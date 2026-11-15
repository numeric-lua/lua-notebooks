# lovr-ent patterns (reference)

Upstream: <https://github.com/mcclure/lovr-ent> (LÖVR 0.13-era sample project;
read the concepts, not the literal calls).

## Useful ideas

- **Apps as entities.** A game/app is an object with `onLoad`, `onUpdate`, and
  `onDraw` hooks. The host can swap or run multiple apps in one process.
- **Entity tree.** Children transform/update with parents; useful for notebook
  cell extension surfaces and scenes.
- **Multiple surfaces.** Render each app into its own `Pass`/`Texture`, then
  composite the textures into one window. This is the closest native analogue
  to an iframe for Jupyter-style widgets.
- **2D mirror UI.** A simple immediate-mode 2D UI drawn on the desktop mirror
  while the 3D scene renders in the headset/window.
- **Threaded asset loading.** Offload loading to a side thread and hand results
  back over a channel.

## Caveats

`lovr-ent` targets 0.13. In 0.19:

- rendering is recorded through `Pass` objects (`lovr.graphics.newPass`,
  `pass:plane`, `pass:text`, `pass:setProjection`);
- `lovr.graphics.getWindowPass()` is the main output pass;
- use textures with the `render` usage as render targets;
- prefer `lovr.thread` + `Channel` over old `lovr.thread` APIs.

License: custom "Other" license in the upstream repository. This is a summary,
not vendored code.
