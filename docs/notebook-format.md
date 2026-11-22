# Notebook document format

Version 1 uses JSON:

```json
{
  "version": 1,
  "name": "welcome.luanb",
  "cells": [
    {
      "kind": "code",
      "source": "print('hello')",
      "output": "",
      "scene": null
    },
    {
      "kind": "markdown",
      "source": "# A notebook"
    }
  ]
}
```

Optional cell fields include `collapsed` for a Markdown heading and
`output_expanded` for a long text output; both default to `false` when absent.
They are view state stored with the document, not executable content.

Rules:

- `kind` is `code` or `markdown`.
- `source` is UTF-8.
- `output` is captured text; `scene` is an optional scene identifier/IR.
- Outputs are not executed on load.
- The schema is additive; unknown fields are preserved by future readers.
- File extension: `.luanb`.
- Keep it Git-friendly: no base64 images or binary assets in the document.
