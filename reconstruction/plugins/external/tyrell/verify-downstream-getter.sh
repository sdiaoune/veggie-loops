#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$source_dir/../../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/external/tyrell/downstream-public-getter-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
 -fsanitize=address,undefined -fno-sanitize-recover=all "$source_dir/downstream-getter.cpp" \
 "$source_dir/downstream-test-contract.cpp" -o "$work_dir/test_contract"
codesign --force --sign - "$work_dir/test_contract"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work_dir/test_contract" > "$work_dir/contract.log" 2>&1
clang++ -arch x86_64 -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -Wno-deprecated-declarations -fsanitize=address,undefined -fno-sanitize-recover=all \
 -framework Cocoa "$source_dir/downstream-getter.cpp" "$source_dir/downstream-test-getter.mm" \
 -o "$work_dir/test_native"
codesign --force --sign - "$work_dir/test_native"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$work_dir/test_native" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst' > "$work_dir/native.log" 2>&1
python3 - "$source_dir" "$work_dir" <<'PY'
import hashlib,json,pathlib,sys
source,work=map(pathlib.Path,sys.argv[1:])
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def result(p):
 data=p.read_text();assert not any(x in data for x in ['runtime error:','Sanitizer','UndefinedBehavior']),data
 d=[json.loads(x) for x in data.splitlines() if x.startswith('{')]
 assert len(d)==1;return d[0]
files=['downstream-getter.h','downstream-getter.cpp','downstream-test-contract.cpp','downstream-test-getter.mm','DOWNSTREAM_GETTER.md','verify-downstream-getter.sh']
report={'status':'builder_verified_pending_independent_review','source_sha256':{p:digest(source/p) for p in files},
 'results':{'contract':result(work/'contract.log'),'native':result(work/'native.log')},
 'log_sha256':{p:digest(work/p) for p in ['contract.log','native.log']},
 'artifacts_sha256':{p:digest(work/p) for p in ['test_contract','test_native']},
 'full_plugin_equivalence':False,'native_class_abi':False,'notifier_scheduling':False}
(work/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['results'],indent=2))
PY
