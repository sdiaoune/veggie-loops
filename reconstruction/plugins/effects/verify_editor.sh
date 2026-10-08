#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work="$repo/.tools/plugin-work/effects/editor-check"
mkdir -p "$work"
compiler=${CXX:-clang++}
"$compiler" -std=c++20 -O2 -fobjc-arc -ffp-contract=off -fno-fast-math \
  -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror \
  "$repo/reconstruction/plugins/effects/balance_plugin.cpp" \
  "$repo/reconstruction/plugins/effects/balance_editor.mm" \
  "$repo/reconstruction/plugins/effects/test_balance_editor.mm" -framework Cocoa \
  -o "$work/test_balance_editor"
"$work/test_balance_editor"
"$compiler" -std=c++20 -O2 -fobjc-arc -DVL_BALANCE_APPKIT_EDITOR=1 \
  -ffp-contract=off -fno-fast-math -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp \
  -Wall -Wextra -Werror -dynamiclib \
  "$repo/reconstruction/plugins/effects/balance_plugin.cpp" \
  "$repo/reconstruction/plugins/effects/balance_native_abi.cpp" \
  "$repo/reconstruction/plugins/effects/balance_editor.mm" -framework Cocoa \
  -o "$work/VLBalanceNativeEditor.dylib"
"$compiler" -std=c++20 -O2 -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations \
  "$repo/reconstruction/plugins/effects/test_balance_native_editor.mm" -framework Cocoa \
  -o "$work/test_balance_native_editor"
engine=${1:-'/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib'}
"$work/test_balance_native_editor" "$engine" "$work/VLBalanceNativeEditor.dylib"
