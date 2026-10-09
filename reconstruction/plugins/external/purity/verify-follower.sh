#!/bin/bash
set -euo pipefail
purity_module="$(cd "$(dirname "$0")" && pwd)"
purity_repo="$(cd "$purity_module/../../../.." && pwd)"
purity_work="$purity_repo/.tools/plugin-work/external/purity/follower"
mkdir -p "$purity_work"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-pow \
  -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all \
  -dynamiclib "$purity_module/envelope_curve.cpp" "$purity_module/envelope_follower.cpp" \
  -o "$purity_work/libvl_purity_follower.dylib"
clang++ -std=c++20 -O1 -ffp-contract=off -fno-fast-math -fobjc-arc -Wno-deprecated-declarations \
  -fsanitize=address,undefined -fno-sanitize-recover=all \
  "$purity_module/test_envelope_follower.mm" -framework Foundation \
  -o "$purity_work/test-purity-follower"
"$purity_work/test-purity-follower" \
  '/Library/Audio/Plug-Ins/VST/SonicCat/Purity.vst/Contents/MacOS/Purity' \
  "$purity_work/libvl_purity_follower.dylib" > "$purity_work/result.json"
cat "$purity_work/result.json"
