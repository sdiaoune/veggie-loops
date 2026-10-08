#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
work="$repo/.tools/plugin-work/generators"
reports="$repo/analysis/plugins/generators/three-osc"
mkdir -p "$work" "$reports"
compiler=${CXX:-clang++}
flags='-std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror'
# All outputs are private build artifacts, not copies staged for distribution.
# Intentional word splitting expands this fixed compiler flag list.
"$compiler" $flags -dynamiclib "$repo/reconstruction/plugins/generators/three_osc.cpp" \
  -o "$work/libvl_three_osc.dylib"
"$compiler" $flags -dynamiclib "$repo/reconstruction/plugins/generators/three_osc_engine.cpp" \
  -o "$work/libvl_three_osc_engine.dylib"
if [ "${1:-}" = '--native' ]; then
  original=${2:-'/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib'}
  lipo "$original" -thin arm64 -output "$work/three-osc-engine.arm64.dylib"
  for test in three_osc three_osc_tables three_osc_exports; do
    "$compiler" $flags -Wno-deprecated-declarations \
      "$repo/reconstruction/plugins/generators/test_$test.cpp" -o "$work/test_$test"
  done
  "$work/test_three_osc" "$original" "$work/three-osc-engine.arm64.dylib" \
    "$reports/differential-tests.json"
  "$work/test_three_osc_tables" "$original" "$work/libvl_three_osc_engine.dylib" \
    "$reports/table-engine-tests.json"
  "$work/test_three_osc_exports" "$original" "$work/libvl_three_osc_engine.dylib" \
    "$reports/public-abi-tests.json"
  "$compiler" $flags -Wno-deprecated-declarations \
    "$repo/reconstruction/plugins/generators/test_exception_termination.cpp" \
    -o "$work/test_exception_termination"
  helper_offset=$(nm "$work/libvl_three_osc_engine.dylib" | \
    rg ' ___clang_call_terminate$' | cut -d ' ' -f 1)
  "$work/test_exception_termination" "$work/three-osc-engine.arm64.dylib" \
    "$work/libvl_three_osc_engine.dylib" "$helper_offset" \
    "$reports/exception-termination-tests.json"
  python3 "$repo/reconstruction/plugins/generators/summarize_verification.py" "$repo" "$original"
fi
