# lua-notebooks status

## Working

- LÖVR notebook shell with tabs, scrolling, 3D viewports, save/load.
- LuaJIT thread kernels and an experimental POSIX process-kernel backend.
- Process CPU/memory limits and timeout recovery.
- luaplotlib scene rendering.
- Extension manifests, discovery, hot reload, browser, local user extensions,
  and a restricted Lua environment.
- Kernel widgets, editable multiline text, callbacks, persistence.
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
- A real LSP protocol server with semantic type/scope analysis.
- OS-level sandboxing for user extensions (only Lua environment restrictions).
- Native Windows process-kernel **runtime** verification. The Windows spawn,
  stop, and cleanup commands are implemented and unit-tested; CI now runs the
  pure platform/editor tests on windows-latest.
- Remote LuaRocks publishing.
- Full Vim (undo tree, regex semantics, text objects, macros).
- Pixel-level visual regression baselines for cells 4/6/7 now exist under
  `tests/visual/baseline`; broader coverage and CI display runners remain.

## Verify

```sh
make test
./scripts/input-smoke.sh   # needs a seat and /dev/uinput
./scripts/visual-smoke.sh  # needs a display
luarocks make lua-notebooks-0.1.0-1.rockspec --tree=/tmp/luanb-rocks
```
