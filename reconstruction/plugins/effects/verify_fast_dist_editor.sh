#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/effects"
numerical_dir="$project_root/reconstruction/plugins/effects"
shared_dir="$project_root/reconstruction/plugins/effects"
work_dir="$project_root/.tools/plugin-work/effects/fast-dist-editor-check"
mkdir -p "$work_dir/default/VL Fast Dist"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -I "$shared_dir" \
 "$numerical_dir/fast_dist_plugin.cpp" "$source_dir/fast_dist_editor.mm" \
 "$source_dir/test_fast_dist_editor.mm" -o "$work_dir/test_editor"
"$work_dir/test_editor" "$work_dir/editor.png"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -fobjc-arc -framework Cocoa -dynamiclib \
 -DVL_FAST_DIST_APPKIT_EDITOR=1 -I "$shared_dir" "$numerical_dir/fast_dist_plugin.cpp" \
 "$source_dir/fast_dist_native_editor_candidate.cpp" "$source_dir/fast_dist_editor.mm" \
 -o "$work_dir/VLFastDistNativeEditor.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_fast_dist_native_editor.mm" -o "$work_dir/test_native_editor"
"$work_dir/test_native_editor" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/VLFastDistNativeEditor.dylib"
# Replay the reviewed no-editor loader and real-provider fixtures against the
# same candidate wrapper compiled without its optional macro.
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -dynamiclib -I "$shared_dir" \
 "$numerical_dir/fast_dist_plugin.cpp" "$source_dir/fast_dist_native_editor_candidate.cpp" \
 -o "$work_dir/default/VL Fast Dist/VL Fast Dist_X64.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_fast_dist_engine_loader.mm" -o "$work_dir/test_default_loader"
"$work_dir/test_default_loader" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/default/VL Fast Dist/VL Fast Dist.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa -I "$shared_dir" \
 "$source_dir/test_fast_dist_engine_stream.mm" -o "$work_dir/test_default_stream"
"$work_dir/test_default_stream" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work_dir/default/VL Fast Dist/VL Fast Dist_X64.dylib"
