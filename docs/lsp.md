# LSP service

`notebook/editor_text.lua` is the in-process editor helper used by the notebook
(diagnostics, completion, hover, textual edits).

`notebook/lsp/framing.lua` and `notebook/lsp/server.lua` implement a real
JSON-RPC LSP core:

- Content-Length framing with split-chunk buffering and size limits;
- initialize/initialized/shutdown lifecycle;
- `textDocument/didOpen`, `didChange`, `didClose`;
- `publishDiagnostics` using the same Lua compile check as the editor;
- completion and hover;
- explicit JSON null and empty object/array encoding.

It is transport-independent and tested through `tests/lsp_protocol.lua`.
The standalone stdio service is `notebook/lsp_server.lua`:

```sh
scripts/lua-notebooks-lsp < framed-input > framed-output
```

A LÖVR channel transport, worker thread, versioned cell documents, and
scope-aware semantic analysis remain to be integrated.
