#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/effects"
shared_dir="$project_root/reconstruction/plugins/effects"
work_dir="$project_root/.tools/plugin-work/effects/fast-dist-engine-stream-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -dynamiclib -I "$shared_dir" "$source_dir/fast_dist_plugin.cpp" \
 "$source_dir/fast_dist_native_abi.cpp" -o "$work_dir/VLFastDistStream.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_fast_dist_engine_stream.mm" -o "$work_dir/test_stream"
"$work_dir/test_stream" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/VLFastDistStream.dylib"
