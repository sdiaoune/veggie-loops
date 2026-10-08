#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/mute2-loader-check"
mkdir -p "$work_dir/VL Mute 2"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -dynamiclib \
  "$project_root/reconstruction/plugins/effects/mute2_plugin.cpp" \
  "$project_root/reconstruction/plugins/effects/mute2_native_abi.cpp" -o "$work_dir/VL Mute 2/VL Mute 2_X64.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/test_mute2_engine_loader.mm" -o "$work_dir/test_mute2_engine_loader"
"$work_dir/test_mute2_engine_loader" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' \
  "$work_dir/VL Mute 2/VL Mute 2.dylib"
