#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/external/tyrell"
work_dir="$project_root/.tools/plugin-work/external/tyrell/parameter-scale-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
 -fsanitize=address,undefined -fno-omit-frame-pointer \
 "$source_dir/tyrell_parameter_scale.cpp" "$source_dir/test_tyrell_parameter_contract.cpp" \
 -o "$work_dir/test_contract"
"$work_dir/test_contract"
clang++ -arch x86_64 -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa \
 "$source_dir/tyrell_parameter_scale.cpp" "$source_dir/test_tyrell_parameter_scale.mm" \
 -o "$work_dir/test_native"
codesign --force --sign - "$work_dir/test_native"
"$work_dir/test_native" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst'
