#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/stereo-shaper-check"
mkdir -p "$work_dir/private"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
  -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror -dynamiclib \
  "$project_root/reconstruction/plugins/effects/stereo_shaper_plugin.cpp" -o "$work_dir/VLStereoShaper.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
  -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/test_stereo_shaper_factory.mm" -o "$work_dir/test_stereo_shaper_factory"
"$work_dir/test_stereo_shaper_factory" \
  '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Stereo Shaper/Fruity Stereo Shaper_x64.dylib' \
  "$work_dir/private/" "$work_dir/VLStereoShaper.dylib"
