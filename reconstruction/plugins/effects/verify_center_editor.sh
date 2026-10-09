#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/effects"
shared_dir="$project_root/reconstruction/plugins/effects"
work_dir="$project_root/.tools/plugin-work/effects/center-editor-check"
mkdir -p "$work_dir/default/VL Center"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -I "$shared_dir" \
 "$source_dir/center_plugin.cpp" "$source_dir/center_editor.mm" \
 "$source_dir/test_center_editor.mm" -o "$work_dir/test_editor"
"$work_dir/test_editor" "$work_dir/editor.png"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -dynamiclib \
 -DVL_CENTER_APPKIT_EDITOR=1 -I "$shared_dir" "$source_dir/center_plugin.cpp" \
 "$source_dir/center_native_editor_candidate.cpp" "$source_dir/center_editor.mm" \
 -o "$work_dir/VLCenterNativeEditor.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_center_native_editor.mm" -o "$work_dir/test_native_editor"
"$work_dir/test_native_editor" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/VLCenterNativeEditor.dylib"
# Replay the reviewed no-editor loader and real-provider fixtures against the
# same candidate wrapper compiled without its optional macro.
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -dynamiclib -I "$shared_dir" \
 "$source_dir/center_plugin.cpp" "$source_dir/center_native_editor_candidate.cpp" \
 -o "$work_dir/default/VL Center/VL Center_X64.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_center_engine_loader.mm" -o "$work_dir/test_default_loader"
"$work_dir/test_default_loader" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/default/VL Center/VL Center.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_center_engine_stream.mm" -o "$work_dir/test_default_stream"
"$work_dir/test_default_stream" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/default/VL Center/VL Center_X64.dylib"
