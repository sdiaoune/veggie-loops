#!/bin/sh
set -eu
candidate=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${VL_IMMEDIATE_CONTEXT_PROJECT_ROOT:-$(CDPATH= cd -- "$candidate/../../../.." && pwd)}
source="$project/reconstruction/plugins/generators"
work="$project/.tools/plugin-work/generators/live-context-public/extra-O0"
mkdir -p "$work"
clang++ -std=c++20 -O0 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -I "$candidate" -I "$source" -dynamiclib -framework Accelerate "$candidate/immediate_factory.cpp" "$candidate/immediate_channel.cpp" "$source/three_osc_sync_lfo.cpp" "$source/three_osc_voice_lifecycle.cpp" "$source/three_osc_declick.cpp" "$source/three_osc_wrapper_core.cpp" "$source/three_osc_engine.cpp" -o "$work/VL 3 Osc_X64.dylib"
for pair in 'prevoice:test_immediate_prevoice_regression' 'live:test_immediate_live_regression' 'preparation:test_immediate_preparation';do
 prefix=${pair%%:*};test=${pair#*:}
 "$project/.tools/plugin-work/generators/live-context-public/canonical-native/$test" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$work/VL 3 Osc_X64.dylib" "$work/" > "$work/$prefix-result.json" 2> "$work/$prefix-stderr.log"
 cmp "$work/$prefix-result.json" "$project/.tools/plugin-work/generators/live-context-public/canonical-native/$prefix-result.json"
done
