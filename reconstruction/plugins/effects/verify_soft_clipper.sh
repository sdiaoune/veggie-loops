#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/soft-clipper-factory-check"
mkdir -p "$work_dir"
source_dir="$project_root/reconstruction/plugins/effects"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
 -Wall -Wextra -Werror -dynamiclib "$source_dir/soft_clipper_plugin.cpp" -o "$work_dir/VLSoftClipperNumerical.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa \
 "$source_dir/test_soft_clipper_factory.mm" -o "$work_dir/test_soft_clipper_factory"
"$work_dir/test_soft_clipper_factory" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Soft Clipper/Fruity Soft Clipper_x64.dylib' \
 "$project_root/.tools/plugin-work/effects/" "$work_dir/VLSoftClipperNumerical.dylib"
