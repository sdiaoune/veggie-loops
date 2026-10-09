#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/phase_inverter-loader-check"
mkdir -p "$work_dir/VL Phase Inverter"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -dynamiclib \
  "$project_root/reconstruction/plugins/effects/phase_inverter_plugin.cpp" \
  "$project_root/reconstruction/plugins/effects/phase_inverter_native_abi.cpp" -o "$work_dir/VL Phase Inverter/VL Phase Inverter_X64.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/test_phase_inverter_engine_loader.mm" -o "$work_dir/test_phase_inverter_engine_loader"
"$work_dir/test_phase_inverter_engine_loader" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' \
  "$work_dir/VL Phase Inverter/VL Phase Inverter.dylib"
