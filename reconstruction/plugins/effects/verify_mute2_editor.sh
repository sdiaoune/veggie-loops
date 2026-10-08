#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/mute2-editor-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -fobjc-arc -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/mute2_plugin.cpp" \
  "$project_root/reconstruction/plugins/effects/mute2_editor.mm" \
  "$project_root/reconstruction/plugins/effects/test_mute2_editor.mm" -o "$work_dir/test_mute2_editor"
"$work_dir/test_mute2_editor"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror -fobjc-arc -framework Cocoa \
  -DVL_MUTE2_APPKIT_EDITOR=1 -dynamiclib \
  "$project_root/reconstruction/plugins/effects/mute2_plugin.cpp" \
  "$project_root/reconstruction/plugins/effects/mute2_native_abi.cpp" \
  "$project_root/reconstruction/plugins/effects/mute2_editor.mm" -o "$work_dir/VLMute2NativeEditor.dylib"
clang++ -std=c++20 -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations -fobjc-arc -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/test_mute2_native_editor.mm" -o "$work_dir/test_mute2_native_editor"
"$work_dir/test_mute2_native_editor" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' \
  "$work_dir/VLMute2NativeEditor.dylib"
