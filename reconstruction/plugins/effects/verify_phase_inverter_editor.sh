#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/phase-inverter-editor-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
  -fobjc-arc -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/phase_inverter_plugin.cpp" \
  "$project_root/reconstruction/plugins/effects/phase_inverter_editor.mm" \
  "$project_root/reconstruction/plugins/effects/test_phase_inverter_editor.mm" -o "$work_dir/test_phase_inverter_editor"
"$work_dir/test_phase_inverter_editor"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
  -fobjc-arc -framework Cocoa -dynamiclib -DVL_PHASE_INVERTER_APPKIT_EDITOR=1 \
  "$project_root/reconstruction/plugins/effects/phase_inverter_plugin.cpp" \
  "$project_root/reconstruction/plugins/effects/phase_inverter_editor.mm" \
  "$project_root/reconstruction/plugins/effects/phase_inverter_native_abi.cpp" -o "$work_dir/VLPhaseInverterNativeEditor.dylib"
clang++ -std=c++20 -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Cocoa \
  "$project_root/reconstruction/plugins/effects/test_phase_inverter_native_editor.mm" -o "$work_dir/test_phase_inverter_native_editor"
"$work_dir/test_phase_inverter_native_editor" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' \
  "$work_dir/VLPhaseInverterNativeEditor.dylib"
