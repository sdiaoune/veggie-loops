#!/bin/sh
# Public reproducible entrypoint. Default compiles original source only;
# --native additionally runs the identity-bound installed-factory corpus.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
WORK="$ROOT/.tools/plugin-work/generators"
mkdir -p "$WORK"
"$HERE/verify-wrapper-core.sh" "$@" > "$WORK/wrapper-core-result.json"
python3 "$HERE/summarize_wrapper.py" "$WORK/wrapper-core-result.json" "$WORK/libvl_three_osc_wrapper_core.dylib"
cat "$WORK/wrapper-core-result.json"
