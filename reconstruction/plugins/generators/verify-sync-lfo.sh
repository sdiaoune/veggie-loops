#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
WORK="$ROOT/.tools/plugin-work/generators"
mkdir -p "$WORK"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -dynamiclib \
 "$ROOT/reconstruction/plugins/generators/three_osc_sync_lfo.cpp" \
 -o "$WORK/libvl_three_osc_sync_lfo.dylib"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror \
 -Wno-deprecated-declarations -framework Cocoa \
 "$ROOT/reconstruction/plugins/generators/test_three_osc_sync_lfo.mm" \
 "$ROOT/reconstruction/plugins/generators/three_osc_legacy_tables.cpp" \
 -o "$WORK/test_three_osc_sync_lfo"
"$WORK/test_three_osc_sync_lfo" \
 "/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib" \
 "$WORK/libvl_three_osc_sync_lfo.dylib" "$WORK/" > "$WORK/sync-lfo-result.json"
python3 "$ROOT/reconstruction/plugins/generators/summarize_sync_lfo.py" \
 "$WORK/sync-lfo-result.json" "$WORK/libvl_three_osc_sync_lfo.dylib"
cat "$WORK/sync-lfo-result.json"
