#!/bin/sh
set -eu
python3 - <<'VL_PYTHON_VERIFICATION_ENV'
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")
VL_PYTHON_VERIFICATION_ENV
candidate=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${VL_IMMEDIATE_CONTEXT_PROJECT_ROOT:-$(CDPATH= cd -- "$candidate/../../../.." && pwd)}
source="$project/reconstruction/plugins/generators"
mode=native
flags=
if [ "$#" -ne 0 ];then
 if [ "$#" -ne 1 ] || [ "$1" != --sanitize ];then echo 'Usage: verify_immediate_context.sh [--sanitize]' >&2;exit 2;fi
 mode=sanitized;flags='-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer'
fi
work=${VL_IMMEDIATE_CONTEXT_WORK_DIR:-"$project/.tools/plugin-work/generators/live-context-public/canonical-$mode"}
mkdir -p "$work/VL 3 Osc"
clang++ -arch arm64 -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $flags -I "$candidate" -I "$source" -dynamiclib -framework Accelerate "$candidate/immediate_factory.cpp" "$candidate/immediate_channel.cpp" "$source/three_osc_sync_lfo.cpp" "$source/three_osc_voice_lifecycle.cpp" "$source/three_osc_declick.cpp" "$source/three_osc_wrapper_core.cpp" "$source/three_osc_engine.cpp" -o "$work/VL 3 Osc/VL 3 Osc_X64.dylib"
codesign --force --sign - "$work/VL 3 Osc/VL 3 Osc_X64.dylib" > "$work/explicit-signature-0.sign.stdout" 2> "$work/explicit-signature-0.sign.stderr"
codesign --verify --strict "$work/VL 3 Osc/VL 3 Osc_X64.dylib" > "$work/explicit-signature-0.verify.stdout" 2> "$work/explicit-signature-0.verify.stderr"
clang++ -arch arm64 -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $flags -I "$source" -framework Cocoa "$candidate/test_immediate_live_regression.mm" "$source/three_osc_legacy_tables.cpp" -o "$work/test_immediate_live_regression"
codesign --force --sign - "$work/test_immediate_live_regression" > "$work/explicit-signature-1.sign.stdout" 2> "$work/explicit-signature-1.sign.stderr"
codesign --verify --strict "$work/test_immediate_live_regression" > "$work/explicit-signature-1.verify.stdout" 2> "$work/explicit-signature-1.verify.stderr"
clang++ -arch arm64 -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $flags -I "$source" -framework Cocoa "$candidate/test_immediate_prevoice_regression.mm" "$source/three_osc_legacy_tables.cpp" "$source/three_osc_clock_context.cpp" -o "$work/test_immediate_prevoice_regression"
codesign --force --sign - "$work/test_immediate_prevoice_regression" > "$work/explicit-signature-2.sign.stdout" 2> "$work/explicit-signature-2.sign.stderr"
codesign --verify --strict "$work/test_immediate_prevoice_regression" > "$work/explicit-signature-2.verify.stdout" 2> "$work/explicit-signature-2.verify.stderr"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work/test_immediate_prevoice_regression" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$work/VL 3 Osc/VL 3 Osc_X64.dylib" "$work/" > "$work/prevoice-result.json" 2> "$work/prevoice-stderr.log"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work/test_immediate_live_regression" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$work/VL 3 Osc/VL 3 Osc_X64.dylib" "$work/" > "$work/live-result.json" 2> "$work/live-stderr.log"
clang++ -arch arm64 -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $flags -I "$source" -framework Cocoa "$candidate/test_immediate_preparation.mm" "$source/three_osc_legacy_tables.cpp" -o "$work/test_immediate_preparation"
codesign --force --sign - "$work/test_immediate_preparation" > "$work/explicit-signature-3.sign.stdout" 2> "$work/explicit-signature-3.sign.stderr"
codesign --verify --strict "$work/test_immediate_preparation" > "$work/explicit-signature-3.verify.stdout" 2> "$work/explicit-signature-3.verify.stderr"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work/test_immediate_preparation" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$work/VL 3 Osc/VL 3 Osc_X64.dylib" "$work/" > "$work/preparation-result.json" 2> "$work/preparation-stderr.log"
mkdir -p "$work/old-lazy"
clang++ -arch arm64 -std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $flags -I "$candidate/lazy-baseline" -I "$source" -dynamiclib -framework Accelerate "$candidate/lazy-baseline/live_context_factory.cpp" "$candidate/lazy-baseline/live_context_channel.cpp" "$source/three_osc_sync_lfo.cpp" "$source/three_osc_voice_lifecycle.cpp" "$source/three_osc_declick.cpp" "$source/three_osc_wrapper_core.cpp" "$source/three_osc_engine.cpp" -o "$work/old-lazy/VL 3 Osc_X64.dylib"
codesign --force --sign - "$work/old-lazy/VL 3 Osc_X64.dylib" > "$work/explicit-signature-4.sign.stdout" 2> "$work/explicit-signature-4.sign.stderr"
codesign --verify --strict "$work/old-lazy/VL 3 Osc_X64.dylib" > "$work/explicit-signature-4.verify.stdout" 2> "$work/explicit-signature-4.verify.stderr"
set +e
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work/test_immediate_preparation" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$work/old-lazy/VL 3 Osc_X64.dylib" "$work/" > "$work/old-lazy-negative.stdout" 2> "$work/old-lazy-negative.stderr"
negative_exit=$?
set -e
if [ "$negative_exit" -ne 1 ];then echo 'Old lazy preparation negative did not reject as expected' >&2;exit 1;fi
python3 - "$work" <<'PY_END'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
for prefix,status in [('prevoice','passed'),('live','passed_live_context_variant'),('preparation','passed_active_immediate_preparation_and_next_use')]:
 s=(p/(prefix+'-stderr.log')).read_text()
 assert not any(x in s for x in ['runtime error:','ERROR: AddressSanitizer','UndefinedBehaviorSanitizer','SUMMARY:']),s
 r=json.loads((p/(prefix+'-result.json')).read_text());assert r['status']==status
 if prefix=='live':assert r['fixtures']==96 and r['fixtures_with_audio_difference']==0 and r['fixtures_with_first_state_difference']==0
 elif prefix=='prevoice':assert r['prevoice_delivery_fixtures']==72 and r['exact_overwritten_audio_floats']==225072
 else:assert r['fixtures']==16 and r['full_fenv_restorations']==240 and r['exact_prepared_words']==44400 and r['immediate_mask_differences']==0 and r['exact_audio_floats']==20352 and r['second_voice_triggers']==16
 print(json.dumps({k:v for k,v in r.items() if k not in ['observations','mask_observations']}))
negative=(p/'old-lazy-negative.stderr').read_text();assert negative=='Preparation mask fixture 0 same-tempo120 native=16 source=0\nImmediate preparation FE masks differ\n',negative
assert not (p/'old-lazy-negative.stdout').read_text()
(p/'old-lazy-negative-result.json').write_text(json.dumps({'status':'passed_expected_rejection','exit':1,'stderr':negative,'full_plugin_equivalence':False},indent=2)+'\n')
PY_END
