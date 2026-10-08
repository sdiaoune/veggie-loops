#!/bin/sh
# Source-only reviewer checks. No installed commercial plugin or captured code
# is loaded. Outputs remain under the review-owned ignored workspace directory.
set -eu
review_repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
review_work="$review_repo/.tools/plugin-work/review/public-boundaries"
review_sources="$review_repo/reconstruction/plugins"
mkdir -p "$review_work"
review_compiler=${CXX:-clang++}
"$review_compiler" -std=c++20 -O1 -g -ffp-contract=off -fno-fast-math \
  -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all \
  "$review_sources/review/wrapper_pitch_boundary.cpp" \
  "$review_sources/generators/three_osc_wrapper_core.cpp" \
  "$review_sources/generators/three_osc_engine.cpp" \
  -o "$review_work/test-wrapper-boundary"
"$review_work/test-wrapper-boundary"
"$review_compiler" -std=c++17 -O1 -g \
  -fsanitize=address,undefined -fno-sanitize-recover=all \
  "$review_sources/review/vst2_host_contract.mm" \
  -framework AppKit -framework CoreFoundation -o "$review_work/test-vst2-contract"
"$review_work/test-vst2-contract"
"$review_compiler" -std=c++20 -O1 -fobjc-arc -DVL_BALANCE_APPKIT_EDITOR=1 \
  -ffp-contract=off -fno-fast-math -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp \
  -dynamiclib "$review_sources/effects/balance_plugin.cpp" \
  "$review_sources/effects/balance_native_abi.cpp" \
  "$review_sources/effects/balance_editor.mm" \
  -framework Cocoa -o "$review_work/VLBalanceEditor.dylib"
"$review_compiler" -std=c++20 -O1 -fobjc-arc \
  "$review_sources/review/balance_editor_tick_thread.mm" \
  -framework Cocoa -o "$review_work/test-editor-worker"
"$review_work/test-editor-worker" "$review_work/VLBalanceEditor.dylib"
