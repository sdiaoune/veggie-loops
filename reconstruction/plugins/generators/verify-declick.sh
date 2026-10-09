#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
WORK="$ROOT/.tools/plugin-work/generators"
mkdir -p "$WORK"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -dynamiclib -framework Accelerate \
 "$ROOT/reconstruction/plugins/generators/three_osc_declick.cpp" -o "$WORK/libvl_three_osc_declick.dylib"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror \
 -Wno-deprecated-declarations -framework Cocoa \
 "$ROOT/reconstruction/plugins/generators/test_three_osc_declick.mm" -o "$WORK/test_three_osc_declick"
"$WORK/test_three_osc_declick" \
 "/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib" \
 "$WORK/libvl_three_osc_declick.dylib" > "$WORK/declick-result.json"
python3 "$ROOT/reconstruction/plugins/generators/summarize_mix_declick.py" declick \
 "$WORK/declick-result.json" "$WORK/libvl_three_osc_declick.dylib"
cat "$WORK/declick-result.json"
