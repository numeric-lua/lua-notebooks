# Curated LÖVR libraries

From <https://lovr.org/docs/Libraries>. Check each repository's license and
LÖVR version before vendoring.

## UI, text, and editors

| library | use | URL |
| --- | --- | --- |
| `iui` | immediate-mode GUI for Lua | https://github.com/DonaldHays/iui |
| `chui` | 3D UI library | https://github.com/jmiskovic/chui |
| `lovr-ui` | immediate-mode VR GUI | https://github.com/immortalx74/lovr-ui |
| `lite-lovr` | lightweight text editor hosted on LÖVR | https://github.com/jmiskovic/lite-lovr |
| `lovr-neovim` | embed Neovim in LÖVR | https://github.com/bjornbytes/lovr-neovim |
| `lovr-letters` | VR keyboard | https://github.com/alloverse/lovr-letters |

## Rendering and scenes

| library | use | URL |
| --- | --- | --- |
| `lovr-ent` | entity tree / app surfaces | https://github.com/mcclure/lovr-ent |
| `lovr-cam` | orbiting camera | https://github.com/jmiskovic/lovr-cam |
| `lovr-atmo` | atmosphere rendering | https://github.com/jmiskovic/lovr-atmo |
| `lovr-base-shading` | base shading helpers | https://github.com/DonaldHays/lovr-base-shading |
| `lovr-icosphere` | icosphere meshes | https://github.com/bjornbytes/lovr-icosphere |
| `lovr-procmesh` | procedural meshes | https://github.com/jmiskovic/lovr-procmesh |
| `lodr` | hot reload | https://github.com/mcclure/lodr |

## Notes

- `lite-lovr` is the closest existing editor integration; it is a reference for
  threading and draw-command transport, not a drop-in notebook UI.
- `iui`/`lovr-ui`/`chui` are candidates for widgets; the first milestone uses a
  small custom immediate-mode cell UI to avoid a large dependency.
- Do not vendor code without recording its license and pinned commit.
