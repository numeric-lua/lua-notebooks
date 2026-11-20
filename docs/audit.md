# Project audit and next work

## Strong points

- Fast LÖVR shell, notebook model, persistent Lua kernels.
- Scene/3-D outputs and luaplotlib rendering.
- Embedded Neovim with real Vim semantics, msgpack-RPC, syntax, mouse,
  save/run/discard, notebook-wide buffer.
- Filetree, markdown/math, widgets, extensions, permissions, LSP, remote gateway.
- Pure tests, Windows process CI, visual CI, LuaRocks release.

## Known fragile areas

1. The custom inline Vim editor is still partial. Neovim is now the default
   editor when `nvim` is available; users without it fall back to the subset.
2. Neovim transport uses POSIX sockets and shell spawning; Windows is unsupported.
3. Neovim grid rendering approximates font advances; long or wide glyphs may
   misalign. External popup menus are disabled until their event shape is verified.
4. Neovim sessions are now reused across cell edits; startup is paid once.
5. Cell layout still computes every cell each frame; visible drawing is culled but
   heights are not cached.
6. Markdown/text layout is not incrementally cached beyond display math.
7. Obsidian-style navigation (backlinks, graph, tags, global search) is absent.
8. OS extension sandboxing is Linux-specific; macOS/Windows use a Lua sandbox.
9. LSP is local and partial; no full semantic index.
10. Visual regression uses a tolerance for renderer variance.

## Next candidates

- Warm Neovim process is reused across cells; startup is paid once.
- Windows Neovim transport (named pipes or TCP FFI definitions).
- Verified external popup-menu rendering and completion tests.
- Cell-height cache and true virtualization; source/output/diagnostic caches landed.
- Markdown links/backlinks and global full-text search.
- macOS/Windows OS sandbox backends.
- Broader visual baselines with renderer pinning.
