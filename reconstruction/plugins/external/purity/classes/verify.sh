#!/bin/bash
set -euo pipefail
classes_source="$(cd "$(dirname "$0")" && pwd)"
classes_repo="$(cd "$classes_source/../../../../.." && pwd)"
classes_work="${VL_PURITY_CLASSES_WORK:-$classes_repo/.tools/plugin-work/review/purity-classes}"
mkdir -p "$classes_work"
classes_flags=(-std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-log10f
  -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all)
clang++ "${classes_flags[@]}" -dynamiclib "$classes_source/live_compressor.cpp" \
  "$classes_source/../peak_compressor.cpp" "$classes_source/../rms_compressor.cpp" \
  -o "$classes_work/libvl_purity_live.dylib"
clang++ "${classes_flags[@]}" -fobjc-arc -Wno-deprecated-declarations \
  "$classes_source/test_live_compressor.mm" -framework Foundation -o "$classes_work/test_live_compressor"
"$classes_work/test_live_compressor" \
  '/Library/Audio/Plug-Ins/VST/SonicCat/Purity.vst/Contents/MacOS/Purity' \
  "$classes_work/libvl_purity_live.dylib" > "$classes_work/result.json"
cat "$classes_work/result.json"
clang++ "${classes_flags[@]}" "$classes_source/test_allocation_failure.cpp" \
  "$classes_source/live_compressor.cpp" "$classes_source/../peak_compressor.cpp" \
  "$classes_source/../rms_compressor.cpp" -o "$classes_work/test_allocation_failure"
"$classes_work/test_allocation_failure" > "$classes_work/allocation-result.json"
cat "$classes_work/allocation-result.json"
python3 "$classes_source/summarize.py" "$classes_work"
