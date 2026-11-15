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
Cross-document definition, references, and rename are implemented over all open
cell documents. Rename uses a Lua-aware lexical-scope index: local declarations and their
references are resolved by block, so shadowed locals are renamed independently.
The parser is still lightweight and does not model function parameters/for-loop
bindings perfectly. `notebook/lsp_edits.lua` validates ranges, applies all edits
atomically with one undo snapshot, and the editor prompt now routes rename
through the async client (with a local fallback).
The standalone stdio service is `notebook/lsp_server.lua`:

```sh
scripts/lua-notebooks-lsp < framed-input > framed-output
```

Cell IDs are persisted in `.luanb`. `notebook/lsp_client.lua` implements
request/notification routing, document sync, versioned cell documents, and
diagnostic caching. It is tested end-to-end against the server core.

A LÖVR channel transport, worker thread, UI wiring, and scope-aware semantic
analysis remain to be integrated.
