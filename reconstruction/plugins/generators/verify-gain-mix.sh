#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
WORK="$ROOT/.tools/plugin-work/generators"
mkdir -p "$WORK"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -dynamiclib \
 "$ROOT/reconstruction/plugins/generators/three_osc_gain_mix.cpp" -o "$WORK/libvl_three_osc_gain_mix.dylib"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror \
 -Wno-deprecated-declarations -framework Cocoa \
 "$ROOT/reconstruction/plugins/generators/test_three_osc_gain_mix.mm" -o "$WORK/test_three_osc_gain_mix"
"$WORK/test_three_osc_gain_mix" \
 "/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib" \
 "$WORK/libvl_three_osc_gain_mix.dylib" > "$WORK/gain-mix-result.json"
python3 "$ROOT/reconstruction/plugins/generators/summarize_mix_declick.py" gain-mix \
 "$WORK/gain-mix-result.json" "$WORK/libvl_three_osc_gain_mix.dylib"
cat "$WORK/gain-mix-result.json"
