#!/bin/sh
set -eu
python3 -c 'import sys; sys.exit("Verification requires Python assertions; unset PYTHONOPTIMIZE and omit -O.") if sys.flags.optimize else None'
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -ne 2 ]; then exit 2; fi
canonical_dir=$1
work_dir=$2
mkdir -p "$work_dir"
for mode in normal sanitized; do
 directory="$work_dir/$mode"
 mkdir -p "$directory"
 test -f "$canonical_dir/$mode/libVLTyrellXY.dylib"
 flags='-std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations'
 if [ "$mode" = sanitized ]; then
  flags="$flags -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer"
 fi
 clang++ -arch x86_64 $flags -framework Cocoa "$source_dir/xy-effects-supplement-fenv.mm" -L "$canonical_dir/$mode" -lVLTyrellXY -Wl,-rpath,"$canonical_dir/$mode" -o "$directory/xy-effects-supplement"
 codesign --force --sign - "$directory/xy-effects-supplement" > "$directory/sign.log" 2>&1
 codesign --verify --strict "$directory/xy-effects-supplement" >> "$directory/sign.log" 2>&1
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$directory/xy-effects-supplement" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst' > "$directory/results.log" 2>&1
done
python3 - "$work_dir" <<'PYREPORT'
import pathlib,json,hashlib,sys
work=pathlib.Path(sys.argv[1]);results={}
for mode in ['normal','sanitized']:
 p=work/mode/'results.log';t=p.read_text();assert not any(s in t for s in ['runtime error:','Sanitizer','UndefinedBehavior'])
 rows=[json.loads(line)for line in t.splitlines()if line.startswith('{')];assert len(rows)==1
 r=rows[0];assert r['status']=='passed_effects_XY_endpoint_order_sticky' and r['cleared_native_pairs']==144 and r['inherited_native_pairs']==144 and r['full_caller_fenv_restorations']==288
 assert r['same_native_allocation_reused'] is False and r['original_byte_or_VFT_patches'] is False and r['full_plugin_equivalence'] is False
 results[mode]=r
assert results['normal']==results['sanitized']
report={'status':'reviewer_endpoint_order_sticky_replay_passed','results':results,'records':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}for p in work.rglob('*')if p.is_file()]}
(work/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(results,indent=2))
PYREPORT
