# AGENTS.md — lua-notebooks

Local instructions for coding agents. The organization-wide rules in
`../AGENTS.md` still apply.

## Scope

`lua-notebooks` is a native LÖVR notebook environment. It is not a web app and
not a JavaScript Jupyter clone.

- **Host owns graphics.** Only `main.lua`, `ui/`, and future extension hosts may
  touch `lovr.graphics`. Kernel code must not receive graphics handles.
- **Kernels are separate Lua states.** One notebook gets one persistent LÖVR
  thread today; process isolation is a later, explicit migration.
- **No unsafe `love`/0.13 LÖVR calls.** Target LÖVR 0.19: `Pass`, `Pass:text`,
  `Pass:plane`, `lovr.thread`, channels.
- Do not add Python, Node, or browser dependencies.
- Keep the notebook document format plain JSON; do not put binary blobs in it.

## Documentation

Before writing LÖVR code, consult:

- `docs/lovr/api/` — original API metadata for every function/object.
- `docs/lovr/library/` — generated LuaLS annotations; `.luarc.json` uses them.
- `docs/lovr/guides/` — upstream guides.
- `docs/references/lovr-ent.md` — entity/app/render-surface patterns.
- `docs/references/lite-lovr.md` — thread/editor/channel architecture.
- `docs/lovr/libraries.md` — UI/editor/scene libraries and licenses.

Do not guess a LÖVR signature. Search the vendored API files first, especially
when a 0.13 example looks different.

## Tests

```sh
make test
LUANB_SMOKE=1 lovr .
LUANB_SMOKE_SCENE=1 lovr .
LUANB_SMOKE_PLOT=1 lovr .
LUANB_SMOKE_SAVE=1 lovr .
```

Every behavior change needs a pure-Lua test when possible; graphics/thread
changes need at least one smoke run. Do not make a real window the only test.

## Rules

- No network at runtime.
- Do not commit generated media, `.lovrshadercache/`, logs, or screenshots.
- Keep vendored docs reproducible; record upstream source/version.
- Do not run git commit/push unless the coordinator asks.
