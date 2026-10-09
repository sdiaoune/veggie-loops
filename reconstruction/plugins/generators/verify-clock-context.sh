#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$source_dir/../../.." && pwd)
mode=native
sanitize_flags=
if [ "$#" -ne 0 ]; then
 if [ "$#" -ne 1 ] || [ "$1" != --sanitize ]; then
  echo 'Usage: verify-clock-context.sh [--sanitize]' >&2
  exit 2
 fi
 mode=sanitized
 sanitize_flags='-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer'
fi
work_dir=${VL_OSC_CLOCK_WORK_DIR:-"$project_root/.tools/plugin-work/generators/clock-context-$mode"}
mkdir -p "$work_dir"
# Fixed flag strings only. No installed source image is instrumented or changed.
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $sanitize_flags -dynamiclib "$source_dir/three_osc_clock_context.cpp" -o "$work_dir/libVLClockContext.dylib"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $sanitize_flags -framework Cocoa "$source_dir/test_three_osc_clock_context.mm" "$work_dir/libVLClockContext.dylib" -o "$work_dir/test_clock_context"
"$work_dir/test_clock_context" > "$work_dir/result.json"
cat "$work_dir/result.json"
