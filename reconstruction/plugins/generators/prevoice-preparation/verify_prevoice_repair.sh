#!/bin/sh
set -eu
python3 - <<'VL_VERIFY_ENV'
import os,sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")
if os.environ.get("VL_PREVOICE_REPAIR_EXECUTION_COPY") != "1":
    raise SystemExit("Run the published verify_public.py entrypoint.")
VL_VERIFY_ENV
candidate=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${VL_PREVOICE_REPAIR_PROJECT_ROOT:-$(CDPATH= cd -- "$candidate/../../../.." && pwd)}
source="$project/reconstruction/plugins/generators"
mode=native;opt=-O2;flags=
case ${1-} in '') ;; --sanitize) mode=sanitized;flags='-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer';; --O0) mode=O0;opt=-O0;; *) echo 'Usage: verify_prevoice_repair.sh [--sanitize|--O0]' >&2;exit 2;; esac
[ "$#" -le 1 ] || exit 2
work=${VL_PREVOICE_REPAIR_WORK_DIR:-"$candidate/work/canonical-$mode"}
mkdir -p "$work/VL 3 Osc" "$work/compiler-cache"
export CLANG_MODULE_CACHE_PATH="$work/compiler-cache"
export ASAN_OPTIONS=halt_on_error=1
export UBSAN_OPTIONS=halt_on_error=1
headroom(){ python3 - "$work" <<'PY'
import os,sys
s=os.statvfs(sys.argv[1]);free=s.f_bavail*s.f_frsize
if free<32*1024*1024:raise SystemExit('Insufficient headroom; preserve outputs and stop without retry')
PY
}
headroom
# core.cpp is included exactly once by prevoice_factory.cpp; it is not a link input.
clang++ -arch arm64 -std=c++20 "$opt" -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $flags -I "$candidate" -I "$source" -dynamiclib -framework Accelerate "$candidate/prevoice_factory.cpp" "$candidate/prevoice_channel.cpp" "$source/three_osc_sync_lfo.cpp" "$source/three_osc_voice_lifecycle.cpp" "$source/three_osc_declick.cpp" "$source/three_osc_engine.cpp" -o "$work/VL 3 Osc/VL 3 Osc_X64.dylib" > "$work/compile-module.stdout" 2> "$work/compile-module.stderr"
codesign --force --sign - "$work/VL 3 Osc/VL 3 Osc_X64.dylib" > "$work/sign-module.stdout" 2> "$work/sign-module.stderr"
codesign --verify --strict "$work/VL 3 Osc/VL 3 Osc_X64.dylib" > "$work/strict-signature-module.stdout" 2> "$work/strict-signature-module.stderr"
for name in cache handoff;do
 headroom
 extra=
 [ "$name" != cache ] || extra="$source/three_osc_clock_context.cpp"
 clang++ -arch arm64 -std=c++20 "$opt" -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $flags -I "$source" -framework Cocoa "$candidate/test_prevoice_$name.mm" "$source/three_osc_legacy_tables.cpp" $extra -o "$work/test_prevoice_$name" > "$work/compile-$name.stdout" 2> "$work/compile-$name.stderr"
 codesign --force --sign - "$work/test_prevoice_$name" > "$work/sign-$name.stdout" 2> "$work/sign-$name.stderr"
 codesign --verify --strict "$work/test_prevoice_$name" > "$work/strict-signature-$name.stdout" 2> "$work/strict-signature-$name.stderr"
 "$work/test_prevoice_$name" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$work/VL 3 Osc/VL 3 Osc_X64.dylib" "$work/" > "$work/$name-result.json" 2> "$work/$name-stderr.log"
done
headroom
clang++ -arch arm64 -std=c++20 "$opt" -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $flags -I "$candidate" -I "$source" "$candidate/test_prevoice_rejections.cpp" -o "$work/test_prevoice_rejections" > "$work/compile-rejections.stdout" 2> "$work/compile-rejections.stderr"
codesign --force --sign - "$work/test_prevoice_rejections" > "$work/sign-rejections.stdout" 2> "$work/sign-rejections.stderr"
codesign --verify --strict "$work/test_prevoice_rejections" > "$work/strict-signature-rejections.stdout" 2> "$work/strict-signature-rejections.stderr"
"$work/test_prevoice_rejections" "$work/VL 3 Osc/VL 3 Osc_X64.dylib" > "$work/rejections-result.json" 2> "$work/rejections-stderr.log"
# All three accepted active/prevoice numeric regressions use immutable sources.
for name in prevoice_regression live_regression preparation;do
 headroom
 extra=
 [ "$name" != prevoice_regression ] || extra="$source/three_osc_clock_context.cpp"
 clang++ -arch arm64 -std=c++20 "$opt" -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations $flags -I "$source" -framework Cocoa "$source/live-context/test_immediate_$name.mm" "$source/three_osc_legacy_tables.cpp" $extra -o "$work/test_immediate_$name" > "$work/compile-$name.stdout" 2> "$work/compile-$name.stderr"
 codesign --force --sign - "$work/test_immediate_$name" > "$work/sign-$name.stdout" 2> "$work/sign-$name.stderr"
 codesign --verify --strict "$work/test_immediate_$name" > "$work/strict-signature-$name.stdout" 2> "$work/strict-signature-$name.stderr"
 "$work/test_immediate_$name" '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib' "$work/VL 3 Osc/VL 3 Osc_X64.dylib" "$work/" > "$work/$name-result.json" 2> "$work/$name-stderr.log"
done
python3 - "$work" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
for name,status in [('cache','passed_bounded_no_voice_preparation_cache'),('handoff','passed_prevoice_cache_handoff'),('rejections','passed_prevoice_source_rejection_atomics'),('prevoice_regression','passed'),('live_regression','passed_live_context_variant'),('preparation','passed_active_immediate_preparation_and_next_use')]:
 s=(p/(name+'-stderr.log')).read_text()
 assert not s,s
 r=json.loads((p/(name+'-result.json')).read_text());assert r['status']==status
 if name=='cache':assert r['measured_callback_pairs']==192 and r['mask_differences']==0 and r['first_trigger_fixtures_with_cache_difference']==0 and r['direct_actual_legacy_phase_consumer_cases']==64
 if name=='handoff':assert r['fixtures']==96 and r['last_voice_channel_recreations']==16
 if name=='prevoice_regression':assert r['prevoice_delivery_fixtures']==72 and r['exact_overwritten_audio_floats']==225072
 if name=='live_regression':assert r['fixtures']==96 and r['fixtures_with_audio_difference']==0
 if name=='preparation':assert r['fixtures']==16 and r['immediate_mask_differences']==0 and r['exact_audio_floats']==20352
 print(json.dumps({k:v for k,v in r.items() if not isinstance(v,list)}))
PY
