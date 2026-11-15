# LÖVR 0.19 cheat sheet for agents

This is a quick index; the full metadata is in `docs/lovr/api/` and
`docs/lovr/library/`.

## Version-critical changes

- LÖVR 0.19 uses **`Pass`** for all drawing: `pass:plane`, `pass:text`,
  `pass:cube`, `pass:setProjection`, `pass:setViewPose`.
- There is no general `lovr.graphics.print`/`lovr.graphics.plane` escape hatch
  to copy from old 0.13 examples.
- **`lovr.graphics.getWindowPass()`** returns the default window pass.
- Render targets are textures created with the `render` usage and attached to
  a `Pass` (`lovr.graphics.newPass`).
- `Pass:setViewport(x, y, w, h)` uses upper-left pixel coordinates; no args
  disables the viewport.
- Use `pass:setProjection("orthographic")` plus a pixel-density-1 font for 2D.

## Threading

- `lovr.thread.newThread(file)` then `Thread:start(...)`; arguments reach the
  thread as `...`.
- `lovr.thread.getChannel(name)` returns a named channel; `Channel:push(value)`
  and `Channel:pop(wait)`.
- Kernel threads do not have graphics objects; send tables/strings instead.
- `lovr.threaderror(thread, message)` fires for uncaught thread errors.

## Input

- `lovr.textinput(text, codepoint)` for typed characters.
- `lovr.keypressed(key, scancode, isrepeat)`.
- `lovr.system.getMousePosition()`, `lovr.system.wasMousePressed(button)`.
- `lovr.system.getClipboardText()`/`setClipboardText()`.

## File system

- `lovr.filesystem.read/write`, `newFile`, `getSaveDirectory`,
  `getSource`, `watch`.
- Writes are confined to the app's save directory; make this visible in UI.

## UI references

- `docs/lovr/examples/Flatscreen/2D_Button/main.lua` — orthographic 2D + text.
- `docs/lovr/examples/Intro/Thread/main.lua` — thread/channel basics.
- `docs/references/lite-lovr.md` — host/thread draw-command editor.
- `docs/references/lovr-ent.md` — entity apps and surfaces.
