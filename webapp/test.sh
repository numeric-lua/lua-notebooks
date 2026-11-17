#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"
for file in js/*.js; do node --check "$file" >/dev/null; done
node --test tests/*.test.mjs
