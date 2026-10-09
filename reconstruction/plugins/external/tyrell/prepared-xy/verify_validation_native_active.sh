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
 flags='-std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -Wno-deprecated-declarations'
 if [ "$mode" = sanitized ]; then
  flags="$flags -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer"
 fi
 clang++ -arch x86_64 $flags -Wno-unused-function -Wno-unused-variable -framework Cocoa "$source_dir/test_validation_native_active.mm" -L "$canonical_dir/$mode" -lVLTyrellXY -Wl,-rpath,"$canonical_dir/$mode" -o "$directory/xy-effects-isolation"
 codesign --force --sign - "$directory/xy-effects-isolation" > "$directory/sign.log" 2>&1
 codesign --verify --strict "$directory/xy-effects-isolation" >> "$directory/sign.log" 2>&1
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$directory/xy-effects-isolation" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst' > "$directory/results.log" 2>&1
done
python3 - "$work_dir" <<'PYREPORT'
import pathlib,json,hashlib,sys
work=pathlib.Path(sys.argv[1]);results={}
for mode in ['normal','sanitized']:
 p=work/mode/'results.log';text=p.read_text();assert not any(s in text for s in ['runtime error:','Sanitizer','UndefinedBehavior'])
 rows=[json.loads(line)for line in text.splitlines()if line.startswith('{')];assert len(rows)==1
 r=rows[0];assert r['status']=='passed_repaired_validation_unused_fields' and r['native_pairs']==9 and r['exact_numerical_and_owned_bytes'] is True and r['source_validation_excess_denormal'] is False
 results[mode]=r
assert results['normal']==results['sanitized']
report={'status':'repaired_validation_unused_fields_native_replayed','results':results,'records':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}for p in work.rglob('*')if p.is_file()]}
(work/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(results,indent=2))
PYREPORT
