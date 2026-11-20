# Stability policy

## Versioning

- 1.x releases keep the notebook JSON format readable.
- New optional fields may be added; unknown fields are preserved only where the
  decoder explicitly retains them.
- Removing a field or changing its meaning requires a major version and a
  migration path.
- `_VERSION` reports the running package version.

## Supported surface

- notebook format (`.luanb`) and filetree operations;
- kernel protocol between the host and workers;
- extension manifest fields: `id`, `version`, `title`, `permissions`,
  `render`, and optional callbacks;
- gateway flags documented in `docs/remote.md`;
- LSP capabilities advertised by `notebook.lsp.server`;
- the optional Neovim bridge when `nvim` is available (experimental).

## Not stable yet

- visual baseline pixels (renderer-dependent);
- internal UI module boundaries;
- experimental remote/process supervisor details;
- undocumented Lua table fields not listed above.
