#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
WORK="$ROOT/.tools/plugin-work/generators"
mkdir -p "$WORK"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -dynamiclib -framework Accelerate \
 "$ROOT/reconstruction/plugins/generators/three_osc_channel.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_voice_lifecycle.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_declick.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_wrapper_core.cpp" \
 "$ROOT/reconstruction/plugins/generators/three_osc_engine.cpp" -o "$WORK/libvl_three_osc_channel.dylib"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror \
 -Wno-deprecated-declarations -framework Cocoa \
 "$ROOT/reconstruction/plugins/generators/test_three_osc_channel.mm" \
 "$ROOT/reconstruction/plugins/generators/three_osc_legacy_tables.cpp" -o "$WORK/test_three_osc_channel"
"$WORK/test_three_osc_channel" \
 "/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib" \
 "$WORK/libvl_three_osc_channel.dylib" "$WORK/" > "$WORK/channel-result.json"
python3 "$ROOT/reconstruction/plugins/generators/summarize_channel.py" \
 "$WORK/channel-result.json" "$WORK/libvl_three_osc_channel.dylib"
cat "$WORK/channel-result.json"
