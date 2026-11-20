# lua-notebooks status

## Working

- LÖVR notebook shell with tabs, scrolling, 3D viewports, save/load.
- LuaJIT thread kernels and an experimental POSIX process-kernel backend.
- Process CPU/memory limits and timeout recovery.
- luaplotlib scene rendering.
- Extension manifests, discovery, hot reload, browser, local user extensions,
  and a restricted Lua environment.
- Kernel widgets, editable multiline text, callbacks, persistence, and live
  shader widgets (Star Nest preset).
- Syntax highlighting, static diagnostics, completion, hover, go-to-definition,
  and workspace rename.
- Hierarchical notebook filetree with create/delete/rename/folder actions.
- Vim mode (default on): insert/normal, cell/character visual, registers,
  yank/paste, undo, search, command line, literal/pattern substitution.
- Inline and display math: symbols, fractions, radicals, simple matrices.
- Collapsible markdown headings and heading outline.
- Command palette, shortcut help, zip package, local install, desktop entry,
  and LuaRocks package/launcher.
- Pure test suite and GitHub Actions CI.
- Manual physical-input and visual smoke scripts.

## Not done

- True TeX/MathJax-quality math layout and fonts.
- Semantic type/scope analysis beyond the current local LSP helpers.
- OS sandboxing is available on Linux through bubblewrap; macOS/Windows use
  the restricted Lua-environment fallback.
- Full Vim semantics: undo tree, regex parity, text objects, macros.
- Broader visual coverage beyond QA cells 4/6/7.

## Verify

```sh
make test
./scripts/input-smoke.sh   # needs a seat and /dev/uinput
./scripts/visual-smoke.sh  # needs a display
luarocks make lua-notebooks-0.1.0-1.rockspec --tree=/tmp/luanb-rocks
```
