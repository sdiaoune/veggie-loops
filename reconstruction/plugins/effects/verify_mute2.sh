#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/mute2-check"
mkdir -p "$work_dir/probe-data"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -dynamiclib \
  "$project_root/reconstruction/plugins/effects/mute2_plugin.cpp" -o "$work_dir/VLMute2.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/test_mute2_factory.mm" -o "$work_dir/test_mute2_factory"
"$work_dir/test_mute2_factory" \
  '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Mute 2/Fruity Mute 2_x64.dylib' \
  "$work_dir/probe-data/" "$work_dir/VLMute2.dylib"
