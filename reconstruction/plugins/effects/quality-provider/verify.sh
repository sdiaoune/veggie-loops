#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$source_dir/../../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/effects/quality-provider-public/check"
mkdir -p "$work_dir"
engine='/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib'
original='/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Fast Dist/Fruity Fast Dist_x64.dylib'
for mode in normal sanitized; do
 extra=''
 if [ "$mode" = sanitized ]; then
  extra='-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer'
 fi
 # The expanded flags are fixed local values above; no external string executes.
 clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
  -fno-builtin-log -Wall -Wextra -Werror -Wno-deprecated-declarations \
  $extra -framework Cocoa "$source_dir/provider_probe.mm" \
  -o "$work_dir/provider-$mode"
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
  "$work_dir/provider-$mode" "$engine" > "$work_dir/provider-$mode.log" 2>&1
 clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp \
  -fno-builtin-log -Wall -Wextra -Werror -Wno-deprecated-declarations \
  $extra -framework Cocoa "$source_dir/provider_original_probe.mm" \
  -o "$work_dir/original-$mode"
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
  "$work_dir/original-$mode" "$engine" "$original" "$source_dir/" \
  > "$work_dir/original-$mode.log" 2>&1
done
python3 - "$source_dir" "$work_dir" <<'PY'
import hashlib,json,pathlib,sys
source,work=map(pathlib.Path,sys.argv[1:])
def entry(p):return {'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
results={}
for name in ['provider-normal','original-normal','provider-sanitized','original-sanitized']:
 p=work/(name+'.log');r=json.loads(p.read_text());assert r['full_plugin_equivalence'] is False
 if name.startswith('provider'):
  assert r['status']=='passed_prepared_actual_mode_provider' and r['calls']==420
 else:
  assert r['status']=='passed_actual_mode_provider_original_fast_dist' and r['actual_provider_calls']==420 and r['opposite_quality_different_samples']>0
 results[name]=r
report={'status':'builder_verified_private_prepared_provider_independent_review_pending','sources':[entry(source/x) for x in ['provider_probe.mm','provider_original_probe.mm','verify.sh']],'model_dependency':entry(source/'../../../../reconstruction/plugins/effects/fast_dist_dsp.hpp'),'results':results,'logs':[entry(work/(n+'.log')) for n in results],'artifacts':[entry(work/n) for n in results],'actual_selector_writer':False,'actual_application_lifecycle':False,'full_plugin_equivalence':False}
(work/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(results,indent=2))
PY
