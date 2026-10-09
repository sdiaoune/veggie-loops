#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/stereo-shaper-editor-check"
mkdir -p "$work_dir"
source_dir="$project_root/reconstruction/plugins/effects"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror \
 -fobjc-arc -framework Cocoa "$source_dir/stereo_shaper_plugin.cpp" \
 "$source_dir/stereo_shaper_editor.mm" "$source_dir/test_stereo_shaper_editor.mm" -o "$work_dir/test_editor"
"$work_dir/test_editor" "$work_dir/editor.png"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror \
 -fobjc-arc -framework Cocoa -dynamiclib -DVL_STEREO_SHAPER_APPKIT_EDITOR=1 \
 "$source_dir/stereo_shaper_plugin.cpp" "$source_dir/stereo_shaper_editor.mm" \
 "$source_dir/stereo_shaper_native_abi.cpp" -o "$work_dir/VLStereoShaperNativeEditor.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror \
 -Wno-deprecated-declarations -framework Cocoa \
 "$source_dir/test_stereo_shaper_native_editor.mm" -o "$work_dir/test_native_editor"
"$work_dir/test_native_editor" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/VLStereoShaperNativeEditor.dylib"
