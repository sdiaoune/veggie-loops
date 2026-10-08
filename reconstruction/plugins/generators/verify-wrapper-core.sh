#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MODE="${1:-build}"
case "$MODE" in build|--native) ;; *) echo "Usage: verify-wrapper-core.sh [--native]" >&2;exit 2 ;; esac
WORK="$ROOT/.tools/plugin-work/generators"
mkdir -p "$WORK/wrapper-data"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
  -fno-builtin-log2 -fno-builtin-log2f -dynamiclib \
  "$ROOT/reconstruction/plugins/generators/three_osc_wrapper_core.cpp" \
  "$ROOT/reconstruction/plugins/generators/three_osc_engine.cpp" \
  -o "$WORK/libvl_three_osc_wrapper_core.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Cocoa \
  "$ROOT/reconstruction/plugins/generators/test_three_osc_wrapper_core.mm" \
  -o "$WORK/test_three_osc_wrapper_core"
NATIVE="/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc"
if [ "$MODE" != "--native" ]; then
  echo '{"status":"compiled","native_factory_replay":false,"full_plugin_recompiled":false}'
  exit 0
fi
"$WORK/test_three_osc_wrapper_core" "$NATIVE/3x Osc_x64.dylib" "$NATIVE/engine.dylib" \
  "$WORK/libvl_three_osc_wrapper_core.dylib" "$WORK/wrapper-data/"
