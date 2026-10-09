#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/effects"
shared_dir="$project_root/reconstruction/plugins/effects"
work_dir="$project_root/.tools/plugin-work/effects/center-engine-stream-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -dynamiclib -I "$shared_dir" "$source_dir/center_plugin.cpp" \
 "$source_dir/center_native_abi.cpp" -o "$work_dir/VLCenterStream.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_center_engine_stream.mm" -o "$work_dir/test_stream"
"$work_dir/test_stream" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/VLCenterStream.dylib"
