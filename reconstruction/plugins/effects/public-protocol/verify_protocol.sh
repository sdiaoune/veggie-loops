#!/bin/sh
set -eu
own=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=${VL_BALANCE_PROTOCOL_ROOT:-$(CDPATH= cd -- "$own/../../../.." && pwd)}
shared="$root/reconstruction/plugins/effects"
work=${VL_BALANCE_PROTOCOL_WORK:-"$root/.tools/plugin-work/effects/balance-public-protocol/work"}
original='/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Balance/Fruity Balance_x64.dylib'
engine='/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib'
python3 "$own/verify_manifest.py"
mkdir -p "$work"
lipo "$engine" -thin arm64 -output "$work/FLEngine.arm64.dylib"
for mode in normal sanitized O0; do
 dst="$work/$mode"
 mkdir -p "$dst/VL Balance"
 flags='';optimization='-O2'
 if [ "$mode" = sanitized ]; then flags='-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer'; fi
 if [ "$mode" = O0 ]; then optimization='-O0'; fi
 common="-std=c++20 $optimization -fno-fast-math -ffp-contract=off -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror"
 clang++ $common $flags -I "$shared" -dynamiclib "$shared/balance_native_abi.cpp" "$shared/balance_plugin.cpp" -o "$dst/VL Balance/VL Balance_X64.dylib"
 clang++ $common $flags -I "$shared" -dynamiclib "$own/protocol_probe.cpp" "$shared/balance_plugin.cpp" -o "$dst/protocol-probe.dylib"
 clang++ $common $flags -Wno-deprecated-declarations -I "$shared" -framework Cocoa "$own/test_protocol.mm" -o "$dst/test_protocol"
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$dst/test_protocol" "$original" "$dst/" "$dst/protocol-probe.dylib" > "$dst/protocol.json" 2> "$dst/protocol.stderr"
 clang++ $common $flags -I "$shared" "$own/test_lifetime.cpp" "$shared/balance_plugin.cpp" -o "$dst/test_lifetime"
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$dst/test_lifetime" > "$dst/lifetime.json" 2> "$dst/lifetime.stderr"
 if [ "$mode" != O0 ]; then
  clang++ $common $flags -x objective-c++ -fobjc-arc -DVL_BALANCE_APPKIT_EDITOR=1 -I "$shared" -framework Cocoa "$own/test_lifetime.cpp" "$shared/balance_plugin.cpp" "$shared/balance_editor.mm" -o "$dst/test_lifetime_editor"
  ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$dst/test_lifetime_editor" > "$dst/lifetime-editor.json" 2> "$dst/lifetime-editor.stderr"
  clang++ $common $flags -Wno-deprecated-declarations -I "$shared" -framework Cocoa "$shared/test_balance_engine_loader.mm" -o "$dst/test_engine_loader"
  ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$dst/test_engine_loader" "$engine" "$dst/VL Balance/VL Balance.dylib" > "$dst/engine-loader.log" 2> "$dst/engine-loader.stderr"
  clang++ $common $flags -Wno-deprecated-declarations -I "$shared" "$shared/test_balance_native_abi.cpp" -o "$dst/test_engine_abi"
  ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$dst/test_engine_abi" "$engine" "$work/FLEngine.arm64.dylib" "$dst/VL Balance/VL Balance_X64.dylib" > "$dst/engine-abi.log" 2> "$dst/engine-abi.stderr"
 fi
 done
python3 "$own/summarize_protocol.py" "$work"
