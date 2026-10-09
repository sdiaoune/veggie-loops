#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$source_dir/../../.." && pwd)
mode=native
sanitize_flags=
if [ "$#" -ne 0 ]; then
 if [ "$#" -ne 1 ] || [ "$1" != --sanitize ]; then
  echo 'Usage: verify-three-osc-native-factory.sh [--sanitize]' >&2
  exit 2
 fi
 mode=sanitized
 sanitize_flags='-fsanitize=address,undefined,float-cast-overflow -fno-omit-frame-pointer'
fi
work_dir="$project_root/.tools/plugin-work/generators/native-factory-maintained/canonical-$mode"
mkdir -p "$work_dir/VL 3 Osc"
# Fixed flag strings only; original installed binaries are never instrumented.
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $sanitize_flags  -I "$project_root/reconstruction/plugins/generators" -dynamiclib -framework Accelerate  "$source_dir/three_osc_native_factory.cpp"  "$project_root/reconstruction/plugins/generators/three_osc_multimode_channel.cpp"  "$project_root/reconstruction/plugins/generators/three_osc_sync_lfo.cpp"  "$project_root/reconstruction/plugins/generators/three_osc_voice_lifecycle.cpp"  "$project_root/reconstruction/plugins/generators/three_osc_declick.cpp"  "$project_root/reconstruction/plugins/generators/three_osc_wrapper_core.cpp"  "$project_root/reconstruction/plugins/generators/three_osc_engine.cpp"  -o "$work_dir/VL 3 Osc/VL 3 Osc_X64.dylib"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $sanitize_flags  -I "$project_root/reconstruction/plugins/generators" -I "$source_dir" -framework Cocoa  "$source_dir/test_three_osc_native_factory.mm"  "$project_root/reconstruction/plugins/generators/three_osc_legacy_tables.cpp"  -o "$work_dir/test_factory"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $sanitize_flags  -I "$project_root/reconstruction/plugins/generators" -I "$source_dir" -framework Cocoa  "$source_dir/test_three_osc_native_factory_loader.mm" -o "$work_dir/test_loader"
"$work_dir/test_factory"  '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib'  "$work_dir/VL 3 Osc/VL 3 Osc_X64.dylib" "$work_dir/" > "$work_dir/factory-result.json"
"$work_dir/test_loader" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib'  "$work_dir/VL 3 Osc/VL 3 Osc.dylib" > "$work_dir/loader-result.json"
cat "$work_dir/factory-result.json" "$work_dir/loader-result.json"
