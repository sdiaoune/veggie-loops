#!/bin/sh
set -eu
candidate=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${VL_HOST_DELEGATED_PROJECT_ROOT:-$(CDPATH= cd -- "$candidate/../../../.." && pwd)}
shared="$project/reconstruction/plugins/effects"
mode=normal
flags=''
if [ "$#" -ne 0 ];then
 if [ "$#" -ne 1 ] || [ "$1" != --sanitize ];then echo 'Usage: verify_host_delegated.sh [--sanitize]' >&2;exit 2;fi
 mode=sanitized;flags='-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer'
fi
work="$project/.tools/plugin-work/effects/fast-dist-host-delegated-public/canonical-$mode"
mkdir -p "$work/VL Host Dist"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log -Wall -Wextra -Werror $flags -dynamiclib -I "$shared" "$candidate/host_delegated_native.cpp" -o "$work/VL Host Dist/VL Host Dist_X64.dylib"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log -Wall -Wextra -Werror -Wno-deprecated-declarations $flags -framework Cocoa -I "$shared" "$candidate/test_host_delegated.mm" "$shared/fast_dist_plugin.cpp" -o "$work/test_host"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log -Wall -Wextra -Werror -Wno-deprecated-declarations $flags -framework Cocoa -I "$shared" "$candidate/test_host_delegated_stream.mm" -o "$work/test_stream"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work/test_host" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Fast Dist/Fruity Fast Dist_x64.dylib' "$work/VL Host Dist/VL Host Dist_X64.dylib" "$work/VL Host Dist/VL Host Dist.dylib" "$work/" > "$work/host-result.json" 2> "$work/host-stderr.log"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work/test_stream" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$work/VL Host Dist/VL Host Dist_X64.dylib" > "$work/stream-result.json" 2> "$work/stream-stderr.log"
python3 - "$work" <<'PY_CHECK'
from pathlib import Path
import json,sys
w=Path(sys.argv[1]);results={}
for name,status in [('host','passed_host_delegated_original_adapters_loader'),('stream','passed_host_delegated_real_stream')]:
 assert (w/(name+'-stderr.log')).read_bytes()==b'',(w/(name+'-stderr.log')).read_text()
 r=json.loads((w/(name+'-result.json')).read_text());assert r['status']==status and r['full_plugin_equivalence'] is False
 if name=='host':assert r['render_callbacks']==7200 and r['host_ordinal24_calls']==4800 and r['total_original_and_delegated_DistWave_calls']==7200 and r['opposite_quality_differences']>0 and r['callback_slots_exercised_across_two_adapters']==40 and r['atomic_audio_rejections']==431
 else:assert r['state_saves']==128 and r['state_restores']==128 and r['hresult_return_bits']==32 and r['completion_store_bits']==32 and r['failed_hresult_full_count_rejections']==1 and r['short_count_success_rejections']==1
 results[name]=r
(w/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps(results))
PY_CHECK
