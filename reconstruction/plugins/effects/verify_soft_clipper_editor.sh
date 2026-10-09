#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/soft-clipper-editor-check"
source_dir="$project_root/reconstruction/plugins/effects"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
 -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -I "$source_dir" \
 "$source_dir/soft_clipper_plugin.cpp" "$source_dir/soft_clipper_editor.mm" \
 "$source_dir/test_soft_clipper_editor.mm" -o "$work_dir/test_editor"
"$work_dir/test_editor" "$work_dir/editor.png"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
 -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -dynamiclib \
 -DVL_SOFT_CLIPPER_APPKIT_EDITOR=1 -I "$source_dir" "$source_dir/soft_clipper_plugin.cpp" \
 "$source_dir/soft_clipper_native_abi.cpp" "$source_dir/soft_clipper_editor.mm" -o "$work_dir/VLSoftClipperNativeEditor.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$source_dir" \
 "$source_dir/test_soft_clipper_native_editor.mm" -o "$work_dir/test_native_editor"
"$work_dir/test_native_editor" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/VLSoftClipperNativeEditor.dylib"
