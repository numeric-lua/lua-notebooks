#!/bin/sh
# Install the LÖVR WebSocket bridge into a LÖVR 0.19 checkout.
set -eu
if [ $# -ne 1 ]; then
  echo "usage: $0 /path/to/lovr" >&2
  exit 2
fi
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
LOVR=$1
test -f "$LOVR/src/main.c" || { echo "not a LÖVR checkout: $LOVR" >&2; exit 1; }
test -f "$LOVR/CMakeLists.txt" || { echo "not a LÖVR checkout: $LOVR" >&2; exit 1; }
cp "$HERE/lovr_websocket.c" "$LOVR/src/api/lovr_websocket.c"
cp "$HERE/lovr_websocket.h" "$LOVR/src/api/lovr_websocket.h"
python3 - "$LOVR" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
main = root / "src/main.c"
text = main.read_text()
if '#include "api/lovr_websocket.h"' not in text:
    text = text.replace('#include "api/api.h"',
                        '#include "api/api.h"\n#include "api/lovr_websocket.h"', 1)
if 'lovr_websocket_preload(L);' not in text:
    text = text.replace('luax_preload(L);',
                        'luax_preload(L);\n    lovr_websocket_preload(L);', 1)
main.write_text(text)
cmake = root / "CMakeLists.txt"
text = cmake.read_text()
marker = "# lua-notebooks WebSocket bridge"
if marker not in text:
    text += f'''

{marker}
if(EMSCRIPTEN AND TARGET lovr)
  target_sources(lovr PRIVATE "${{CMAKE_CURRENT_SOURCE_DIR}}/src/api/lovr_websocket.c")
  target_link_options(lovr PRIVATE "-lwebsocket.js")
endif()
'''
    cmake.write_text(text)
print("patched", root)
PY
