#!/bin/sh
set -eu
python3 -c 'import sys; sys.exit("Verification requires Python assertions; unset PYTHONOPTIMIZE and omit -O.") if sys.flags.optimize else None'
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -ne 1 ]; then exit 2; fi
work_dir=$1
mkdir -p "$work_dir"
common_flags='-std=c++20 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror'
clang++ -arch x86_64 -O0 $common_flags -dynamiclib "$source_dir/xy-api.cpp" -Wl,-install_name,@rpath/libVLTyrellXY.dylib -o "$work_dir/libVLTyrellXY.dylib"
clang++ -arch x86_64 -O2 $common_flags -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable -framework Cocoa "$source_dir/test_validation_native_o0.mm" -L "$work_dir" -lVLTyrellXY -Wl,-rpath,@loader_path -o "$work_dir/native-o0-observer"
for artifact in libVLTyrellXY.dylib native-o0-observer; do
 codesign --force --sign - "$work_dir/$artifact" > "$work_dir/sign-$artifact.log" 2>&1
 codesign --verify --strict "$work_dir/$artifact" >> "$work_dir/sign-$artifact.log" 2>&1
done
"$work_dir/native-o0-observer" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst' > "$work_dir/results.log" 2>&1
python3 - "$work_dir" <<'PYREPORT'
import pathlib,json,hashlib,sys
work=pathlib.Path(sys.argv[1]);text=(work/'results.log').read_text();assert not any(s in text for s in ['runtime error:','Sanitizer','UndefinedBehavior'])
rows=[json.loads(line)for line in text.splitlines()if line.startswith('{')];assert len(rows)==1
result=rows[0];assert result['status']=='observed_API_O0_coordinate_evaluation_order' and result['native_pairs']==9
report={'status':'API_O0_order_observed_pending_assessment','result':result,'source_O0_harness_O2':True,'records':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}for p in work.rglob('*')if p.is_file()]}
(work/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(result,indent=2))
PYREPORT
