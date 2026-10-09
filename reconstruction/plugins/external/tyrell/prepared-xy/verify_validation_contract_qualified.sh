#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "$#" -ne 1 ]; then exit 2; fi
work_dir=$1
mkdir -p "$work_dir"
for mode in normal sanitized; do
 mkdir -p "$work_dir/$mode"
 flags='-std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror'
 if [ "$mode" = sanitized ]; then
  flags="$flags -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer"
 fi
 for architecture in arm64 x86_64; do
  artifact="$work_dir/$mode/contract-$architecture"
  clang++ -arch "$architecture" $flags "$source_dir/xy-api.cpp" "$source_dir/test_validation_contract_qualified.cpp" -o "$artifact"
  codesign --force --sign - "$artifact" > "$artifact-sign.log" 2>&1
  codesign --verify --strict "$artifact" >> "$artifact-sign.log" 2>&1
  ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$artifact" > "$artifact-results.log" 2>&1
 done
done
python3 - "$work_dir" <<'PYREPORT'
import pathlib,json,hashlib,sys
work=pathlib.Path(sys.argv[1]);results={}
for mode in ['normal','sanitized']:
 for architecture in ['arm64','x86_64']:
  text=(work/mode/f'contract-{architecture}-results.log').read_text();assert not any(s in text for s in ['runtime error:','Sanitizer','UndefinedBehavior'])
  rows=[json.loads(line)for line in text.splitlines()if line.startswith('{')];assert len(rows)==1
  r=rows[0];assert r['status']=='passed_bit_validation_state_and_FP_preservation' and r['calls']==1488 and r['full_fenv_readbacks']==1488 and r['accepted']+r['atomic_rejections']==1488
  results[f'{mode}-{architecture}']=r
assert all(r==results['normal-arm64']for r in results.values())
report={'status':'builder_validation_contract_both_architectures_passed','results':results,'records':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}for p in work.rglob('*')if p.is_file()]}
(work/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(results,indent=2))
PYREPORT
