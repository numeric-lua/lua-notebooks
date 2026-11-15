# Offline LÖVR reference

Vendored documentation for agents working on lua-notebooks.

- **Installed runtime:** LÖVR `0.19.0` (`lovr-bin` on this machine).
- **Docs source:** <https://github.com/bjornbytes/lovr-docs>, cloned at the
  `v0.19.x` documentation line.
- **API definitions:** `docs/lovr/api/` contains the original LÖVR documentation
  metadata (`api/lovr/**/*.lua`, one file per function/object).
- **LuaLS annotations:** `docs/lovr/library/` was generated with
  `lovr api cats` from the same docs. `.luarc.json` points LuaLS at it.
- **Guides:** `docs/lovr/guides/*.md`.
- **Examples:** `docs/lovr/examples/`; binary media was pruned to keep the repo
  small. Example code is CC0 per the upstream README.
- **Libraries:** `docs/lovr/libraries.md` is the curated list from
  <https://lovr.org/docs/Libraries>.

## Regenerating the annotations

From a checkout of `lovr-docs`:

```sh
lovr api cats
# writes api/cats/config.json and api/cats/library/
```

Copy `library/` here. The annotations are generated, not hand-maintained.

## Important version note

LÖVR 0.18 renamed the rendering API around `Pass` and removed many old
`lovr.graphics.*` drawing calls. Code in this repository targets **0.19**.
Do not copy 0.13-era `lovr-ent` calls literally; use the patterns in
`docs/references/lovr-ent.md` and the 0.19 API definitions.
