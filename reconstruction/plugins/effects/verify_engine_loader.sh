#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work="$repo/.tools/plugin-work/effects/engine-loader-check"
mkdir -p "$work/VL Balance"
compiler=${CXX:-clang++}
"$compiler" -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
  -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror -dynamiclib \
  "$repo/reconstruction/plugins/effects/balance_plugin.cpp" \
  "$repo/reconstruction/plugins/effects/balance_native_abi.cpp" \
  -o "$work/VL Balance/VL Balance_X64.dylib"
"$compiler" -std=c++20 -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations \
  "$repo/reconstruction/plugins/effects/test_balance_engine_loader.mm" -framework Cocoa \
  -o "$work/test_balance_engine_loader"
engine=${1:-'/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib'}
"$work/test_balance_engine_loader" "$engine" "$work/VL Balance/VL Balance.dylib"
