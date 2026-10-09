#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/effects"
work_dir="$project_root/.tools/plugin-work/effects/fast-dist-numerical-check"
mkdir -p "$work_dir/empty-resources"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -fno-builtin-exp -fno-builtin-log -Wall -Wextra -Werror \
 -Wno-deprecated-declarations -framework Cocoa \
 "$source_dir/fast_dist_plugin.cpp" "$source_dir/test_fast_dist_factory.mm" \
 -o "$work_dir/test_factory"
"$work_dir/test_factory" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Fast Dist/Fruity Fast Dist_x64.dylib' "$work_dir/empty-resources/" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib'
clang++ -std=c++20 -O1 -g -ffp-contract=off -fno-fast-math \
 -fno-builtin-exp -fno-builtin-log -Wall -Wextra -Werror \
 -fsanitize=address,undefined "$source_dir/test_fast_dist_boundary.cpp" \
 -o "$work_dir/test_boundary"
"$work_dir/test_boundary"
