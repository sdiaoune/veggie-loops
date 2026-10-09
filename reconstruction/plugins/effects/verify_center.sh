#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/effects"
work_dir="$project_root/.tools/plugin-work/effects/center-numerical-check"
mkdir -p "$work_dir/resources"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -dynamiclib "$source_dir/center_plugin.cpp" \
 -o "$work_dir/VLCenter.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -fobjc-arc -Wno-deprecated-declarations -framework Cocoa \
 "$source_dir/test_center_factory.mm" -o "$work_dir/test_factory"
"$work_dir/test_factory" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Center/Fruity Center_x64.dylib' "$work_dir/resources/" "$work_dir/VLCenter.dylib"
