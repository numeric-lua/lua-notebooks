# lite-lovr patterns (reference)

Upstream: <https://github.com/jmiskovic/lite-lovr> (MIT). A text editor hosted
inside LÖVR, based on rxi/lite.

## Relevant architecture

- The editor runs in a **LÖVR thread** with its own Lua environment.
- Host and thread communicate through **two unidirectional channels**.
- The thread cannot call `lovr.graphics`; it emits a serialized list of draw
  commands. The host thread replays them with LÖVR.
- Multiple editor instances are possible; each has its own thread and channels.
- Input events are sent from the host to the focused editor.
- Clipping is implemented with stencils; the 2D UI is drawn on a plane.

## What lua-notebooks borrows

- Separate Lua states for code execution and UI.
- A host/worker channel protocol rather than sharing globals.
- Draw-command/scene output instead of letting kernels touch graphics.
- A bounded worker pool; kernel count must respect it.

## What not to copy

lite-lovr is a full modal editor with many assumptions. The notebook needs a
small cell editor, not a general text editor. Use its threading pattern, not its
UI code, for the first milestone.
