#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$source_dir/../../../.." && pwd)
work_dir="$project_root/.tools/plugin-work/external/tyrell/notifier-public-check"
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-floorf \
 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=all \
 "$source_dir/notifier-storage.cpp" "$source_dir/notifier-contract.cpp" \
 -o "$work_dir/test_contract"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
 "$work_dir/test_contract" > "$work_dir/contract.log" 2>&1
clang++ -arch x86_64 -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -fno-builtin-floorf -Wall -Wextra -Werror -Wno-deprecated-declarations \
 -fsanitize=address,undefined -fno-sanitize-recover=all -framework Cocoa \
 "$source_dir/notifier-storage.cpp" "$source_dir/notifier-native.mm" \
 -o "$work_dir/test_native"
codesign --force --sign - "$work_dir/test_native"
codesign --verify --strict "$work_dir/test_native"
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
 "$work_dir/test_native" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst' \
 > "$work_dir/native.log" 2>&1
python3 - "$source_dir" "$work_dir" <<'PY'
import pathlib,json,hashlib,sys
source,work=map(pathlib.Path,sys.argv[1:])
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def result(p):
 data=p.read_text();assert not any(x in data for x in ['runtime error:','Sanitizer','UndefinedBehavior'])
 rows=[json.loads(x) for x in data.splitlines() if x.startswith('{')]
 assert len(rows)==1 and rows[0]['status'].startswith('passed_');return rows[0]
files=['notifier-storage.h','notifier-storage.cpp','notifier-contract.cpp','notifier-native.mm','NOTIFIER_STORAGE.md','notifier-verify.sh']
report={'status':'builder_verified_independent_review_pending','source_sha256':{f:digest(source/f) for f in files},'results':{f:result(work/(f+'.log')) for f in ['contract','native']},'logs_sha256':{f:digest(work/f) for f in ['contract.log','native.log']},'artifacts_sha256':{f:digest(work/f) for f in ['test_contract','test_native']},'native_callbacks_substituted':False,'whole_native_state_restore':False,'scheduler_production':False,'full_plugin_equivalence':False}
(work/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['results'],indent=2))
PY
