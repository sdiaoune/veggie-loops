#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
MODE=native
SANITIZE_FLAGS=
if [ "$#" -ne 0 ]; then
 if [ "$#" -ne 1 ] || [ "$1" != --sanitize ]; then
  echo 'Usage: multimode-verify.sh [--sanitize]' >&2
  exit 2
 fi
 MODE=sanitized
 SANITIZE_FLAGS='-fsanitize=address,undefined,float-cast-overflow -fno-omit-frame-pointer'
fi
WORK="$ROOT/.tools/plugin-work/generators/multimode-channel/$MODE"
mkdir -p "$WORK"
# SANITIZE_FLAGS contains only the fixed compiler arguments selected above.
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $SANITIZE_FLAGS -dynamiclib -framework Accelerate \
 "$ROOT/reconstruction/plugins/generators/three_osc_multimode_channel.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_sync_lfo.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_voice_lifecycle.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_declick.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_wrapper_core.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_engine.cpp" \
 -o "$WORK/libvl_three_osc_multimode_channel.dylib"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $SANITIZE_FLAGS \
 -Wno-deprecated-declarations -framework Cocoa \
 "$ROOT/reconstruction/plugins/generators/test_three_osc_multimode_channel.mm" \
 "$ROOT/reconstruction/plugins/generators/three_osc_legacy_tables.cpp" \
 -o "$WORK/test_three_osc_multimode_channel"
"$WORK/test_three_osc_multimode_channel" \
 "/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib" \
 "$WORK/libvl_three_osc_multimode_channel.dylib" "$WORK/" > "$WORK/result.json"
python3 "$ROOT/reconstruction/plugins/generators/multimode-summarize.py" \
 "$WORK/result.json" "$WORK/libvl_three_osc_multimode_channel.dylib" "$MODE"
cat "$WORK/result.json"
