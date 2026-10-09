#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/soft-clipper-native-check"
source_dir="$project_root/reconstruction/plugins/effects"
mkdir -p "$work_dir/VL Soft Clipper"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
 -Wall -Wextra -Werror -dynamiclib -I "$source_dir" "$source_dir/soft_clipper_plugin.cpp" \
 "$source_dir/soft_clipper_native_abi.cpp" -o "$work_dir/VL Soft Clipper/VL Soft Clipper_X64.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$source_dir" \
 "$source_dir/test_soft_clipper_engine_loader.mm" -o "$work_dir/test_loader"
"$work_dir/test_loader" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/VL Soft Clipper/VL Soft Clipper.dylib"
