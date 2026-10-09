#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/effects"
shared_dir="$project_root/reconstruction/plugins/effects"
work_dir="$project_root/.tools/plugin-work/effects/fast-dist-native-check"
mkdir -p "$work_dir/VL Fast Dist"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -dynamiclib -I "$shared_dir" "$source_dir/fast_dist_plugin.cpp" \
 "$source_dir/fast_dist_native_abi.cpp" -o "$work_dir/VL Fast Dist/VL Fast Dist_X64.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_fast_dist_engine_loader.mm" -o "$work_dir/test_loader"
"$work_dir/test_loader" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/VL Fast Dist/VL Fast Dist.dylib"
