#!/bin/sh
set -eu
candidate_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=${VL_CONTEXT_DELIVERY_PROJECT_ROOT:-$(CDPATH= cd -- "$candidate_dir/../../.." && pwd)}
source_dir="$project_root/reconstruction/plugins/generators"
mode=native
sanitize_flags=
if [ "$#" -ne 0 ]; then
 if [ "$#" -ne 1 ] || [ "$1" != --sanitize ]; then echo 'Usage: verify-context-delivery.sh [--sanitize]' >&2; exit 2; fi
 mode=sanitized
 sanitize_flags='-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer'
fi
work_dir=${VL_CONTEXT_DELIVERY_WORK_DIR:-"$project_root/.tools/plugin-work/generators/context-delivery-public/canonical-$mode"}
mkdir -p "$work_dir/VL 3 Osc"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $sanitize_flags -I "$source_dir" -dynamiclib -framework Accelerate "$source_dir/three_osc_native_factory.cpp" "$source_dir/three_osc_multimode_channel.cpp" "$source_dir/three_osc_sync_lfo.cpp" "$source_dir/three_osc_voice_lifecycle.cpp" "$source_dir/three_osc_declick.cpp" "$source_dir/three_osc_wrapper_core.cpp" "$source_dir/three_osc_engine.cpp" -o "$work_dir/VL 3 Osc/VL 3 Osc_X64.dylib"
clang++ -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $sanitize_flags -I "$source_dir" -framework Cocoa "$candidate_dir/test_three_osc_context_delivery.mm" "$source_dir/three_osc_legacy_tables.cpp" "$source_dir/three_osc_clock_context.cpp" -o "$work_dir/test_context_delivery"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work_dir/test_context_delivery" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$work_dir/VL 3 Osc/VL 3 Osc_X64.dylib" "$work_dir/" > "$work_dir/result.json" 2> "$work_dir/stderr.log"
python3 - "$work_dir" <<'END_PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);diagnostic=(p/'stderr.log').read_text()
if any(x in diagnostic for x in ('runtime error:', 'ERROR: AddressSanitizer', 'UndefinedBehaviorSanitizer', 'SUMMARY:')): raise SystemExit('Sanitizer diagnostic rejected')
r=json.loads((p/'result.json').read_text())
if r.get('status') != 'passed': raise SystemExit('Replay did not pass')
print(json.dumps(r))
END_PY
