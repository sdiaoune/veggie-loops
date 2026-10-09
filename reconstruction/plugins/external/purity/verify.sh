#!/bin/bash
set -euo pipefail
purity_module="$(cd "$(dirname "$0")" && pwd)"
purity_repo="$(cd "$purity_module/../../../.." && pwd)"
purity_work="$purity_repo/.tools/plugin-work/external/purity/curve"
mkdir -p "$purity_work"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-pow \
  -Wall -Wextra -Werror -dynamiclib "$purity_module/envelope_curve.cpp" \
  -o "$purity_work/libvl_purity_curve.dylib"
clang++ -std=c++20 -O1 -fobjc-arc -Wno-deprecated-declarations \
  -fsanitize=address,undefined -fno-sanitize-recover=all \
  "$purity_module/test_envelope_curve.mm" -framework Foundation \
  -o "$purity_work/test-purity-curve"
"$purity_work/test-purity-curve" \
  '/Library/Audio/Plug-Ins/VST/SonicCat/Purity.vst/Contents/MacOS/Purity' \
  "$purity_work/libvl_purity_curve.dylib" > "$purity_work/result.json"
cat "$purity_work/result.json"
