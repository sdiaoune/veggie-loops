#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
source_dir="$project_root/reconstruction/plugins/external/tyrell"
work_dir=${VL_TYRELL_MANAGER_WORK_DIR:-"$project_root/.tools/plugin-work/review/tyrell-manager/verification"}
mkdir -p "$work_dir"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
 -fsanitize=address,undefined -fno-omit-frame-pointer \
 "$source_dir/tyrell_parameter_scale.cpp" "$source_dir/tyrell_parameter_manager.cpp" \
 "$source_dir/test_tyrell_parameter_manager.cpp" -o "$work_dir/test_contract"
# Sign every generated Intel harness, including source-only runs on Intel Macs.
codesign --force --sign - "$work_dir/test_contract"
"$work_dir/test_contract" > "$work_dir/contract-result.log"
cat "$work_dir/contract-result.log"
clang++ -arch x86_64 -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror \
 -fsanitize=address,undefined -fno-omit-frame-pointer -dynamiclib \
 "$source_dir/tyrell_parameter_scale.cpp" "$source_dir/tyrell_parameter_manager.cpp" \
 -o "$work_dir/VLTyrellParameterManager.dylib"
codesign --force --sign - "$work_dir/VLTyrellParameterManager.dylib"
clang++ -arch x86_64 -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
 -Wall -Wextra -Werror -Wno-deprecated-declarations \
 -fsanitize=address,undefined -fno-omit-frame-pointer -framework Cocoa \
 "$source_dir/tyrell_parameter_scale.cpp" "$source_dir/test_tyrell_parameter_manager.mm" \
 -o "$work_dir/test_native"
codesign --force --sign - "$work_dir/test_native"
"$work_dir/test_native" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst' \
 "$work_dir/VLTyrellParameterManager.dylib" > "$work_dir/native-result.log"
cat "$work_dir/native-result.log"
python3 - "$project_root" "$work_dir" <<'PY'
import hashlib, json, pathlib, sys
root, work = map(pathlib.Path, sys.argv[1:])
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def result(path):
    records = [json.loads(line) for line in path.read_text().splitlines() if line.startswith('{')]
    if len(records) != 1: raise ValueError('Expected one successful result record')
    return records[0]
paths = [
 'reconstruction/plugins/external/tyrell/tyrell_parameter_manager.h',
 'reconstruction/plugins/external/tyrell/tyrell_parameter_manager.cpp',
 'reconstruction/plugins/external/tyrell/test_tyrell_parameter_manager.cpp',
 'reconstruction/plugins/external/tyrell/test_tyrell_parameter_manager.mm',
 'reconstruction/plugins/external/tyrell/verify-parameter-manager.sh',
 'reconstruction/plugins/external/tyrell/PARAMETER_MANAGER.md',
]
dependencies = [
 'reconstruction/plugins/external/tyrell/tyrell_parameter_scale.h',
 'reconstruction/plugins/external/tyrell/tyrell_parameter_scale.cpp',
 'reconstruction/plugins/common/vst2_probe.mm',
]
report = {
 'status': 'builder_verified_pending_independent_review',
 'source_only_contract': result(work/'contract-result.log'),
 'native_differential': result(work/'native-result.log'),
 'source_sha256': {p:digest(root/p) for p in paths},
 'dependency_sha256': {p:digest(root/p) for p in dependencies},
 'artifacts_sha256': {p:digest(work/p) for p in ['test_contract','test_native','VLTyrellParameterManager.dylib']},
 'result_log_sha256': {p:digest(work/p) for p in ['contract-result.log','native-result.log']},
 'target_universal_sha256': 'a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54',
 'target_x86_64_sha256': '8d76659f91ce432b1d58f835b2c6ee1bfd30ac9de61e579500d3c712b22def38',
 'native_slots': {'0x1b8':'0x125630','0x1c8':'0x125780','0x250':'0x1255b0'},
 'native_fixture_architecture': 'x86_64 macOS; every generated harness ad-hoc signed',
 'sanitizers': 'ASan/UBSan source fixture, compiled reconstruction dylib and native fixture; original binary is not instrumented',
 'domain': {
    'descriptors': 'Actual 92 public descriptors, 33 type0/59 type1, known internal IDs only',
    'raw': 'Finite [-4096,4096], no range clamping',
    'clock': 'Every finite float allowed; corpus includes signed zero, subnormal and +/-FLT_MAX',
    'fp': 'nearest-even, gradual subnormals, separate float add then floor, no fast math/FMA contraction',
    'prepared_storage': '92 valid raw values, valid finite clock, lastID=-1 or known internal ID; serialized access',
    'prepared_extra_types': 'Types0,1,2,3,4,5,255 compared using a synthetic descriptor table, not native public controls',
 },
 'substitutions': [
    'Actual nested raw-getter slot0x2d8 is replaced with a controlled return/argument recorder',
    'Actual manager target+0x48 and clock pointer+0x58 are replaced; notifier0x298 synchronously commits prepared raw storage',
    'The separate extra-type corpus substitutes an empty descriptor table, retaining actual public map and manager procedures',
 ],
 'open_gates': ['Native raw/audio backend and scheduling','Native manager class/factory ABI source',
    'Native meter warning logger','Complete state/preset and GUI behavior','Real host integration/RT certificate',
    'Audio DSP reconstruction','Arbitrary NaN/Inf, unsupported internal IDs, or other FP modes'],
 'full_plugin_equivalence': False, 'whole_dsp': False, 'native_class_abi': False,
 'actual_audio_target': False, 'real_host_clock': False,
}
(work/'parameter-manager-verification.json').write_text(json.dumps(report, indent=2)+'\n')
print('Source-bound manifest: '+str(work/'parameter-manager-verification.json'))
PY
