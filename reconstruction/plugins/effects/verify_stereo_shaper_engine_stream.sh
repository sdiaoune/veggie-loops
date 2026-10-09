#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/stereo-shaper-stream-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror -dynamiclib \
  "$project_root/reconstruction/plugins/effects/stereo_shaper_plugin.cpp" \
  "$project_root/reconstruction/plugins/effects/stereo_shaper_native_abi.cpp" -o "$work_dir/VLStereoShaperStream.dylib"
clang++ -std=c++20 -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/test_stereo_shaper_engine_stream.mm" -o "$work_dir/test_stereo_shaper_engine_stream"
"$work_dir/test_stereo_shaper_engine_stream" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' \
  "$work_dir/VLStereoShaperStream.dylib"
