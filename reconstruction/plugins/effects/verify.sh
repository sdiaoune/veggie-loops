#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work="$repo/.tools/plugin-work/effects"
mkdir -p "$work"
compiler=${CXX:-clang++}
# Clang can combine separate sin/cos calls into a different system entry point.
# These flags preserve the target's individual imports and arithmetic rounding.
"$compiler" -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
  -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp \
  "$repo/reconstruction/plugins/effects/test_balance_model.cpp" \
  -o "$work/test_balance_model"
"$work/test_balance_model"
"$compiler" -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
  -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp \
  "$repo/reconstruction/plugins/effects/balance_plugin.cpp" \
  "$repo/reconstruction/plugins/effects/test_balance_api.cpp" \
  -o "$work/test_balance_api"
"$work/test_balance_api"
if [ "${1:-}" = "--native" ]; then
  original=${2:-'/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Balance/Fruity Balance_x64.dylib'}
  lipo "$original" -thin arm64 -output "$work/FruityBalance.arm64.dylib"
  "$compiler" -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
    -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wno-deprecated-declarations \
    "$repo/reconstruction/plugins/effects/test_balance_dsp.cpp" \
    -o "$work/test_balance_dsp"
  "$work/test_balance_dsp" "$original" "$work/FruityBalance.arm64.dylib"
fi
if [ "${1:-}" = "--factory" ]; then
  original=${2:-'/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Balance/Fruity Balance_x64.dylib'}
  mkdir -p "$work/probe-data"
  "$compiler" -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
    -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -dynamiclib \
    "$repo/reconstruction/plugins/effects/balance_plugin.cpp" -o "$work/libVLBalance.dylib"
  "$compiler" -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
    -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wno-deprecated-declarations \
    "$repo/reconstruction/plugins/effects/test_balance_factory.mm" \
    -framework Cocoa -o "$work/test_balance_factory"
  "$work/test_balance_factory" "$original" "$work/probe-data/" "$work/libVLBalance.dylib"
fi
if [ "${1:-}" = "--engine-abi" ]; then
  original=${2:-'/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib'}
  lipo "$original" -thin arm64 -output "$work/FLEngine.arm64.dylib"
  "$compiler" -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
    -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -dynamiclib \
    "$repo/reconstruction/plugins/effects/balance_plugin.cpp" \
    "$repo/reconstruction/plugins/effects/balance_native_abi.cpp" -o "$work/VLBalanceNative.dylib"
  "$compiler" -std=c++20 -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations \
    "$repo/reconstruction/plugins/effects/test_balance_native_abi.cpp" -o "$work/test_balance_native_abi"
  "$work/test_balance_native_abi" "$original" "$work/FLEngine.arm64.dylib" "$work/VLBalanceNative.dylib"
fi
