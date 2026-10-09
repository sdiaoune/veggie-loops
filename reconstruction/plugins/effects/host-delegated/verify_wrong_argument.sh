#!/bin/sh
set -eu
candidate=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project=${VL_HOST_DELEGATED_PROJECT_ROOT:-$(CDPATH= cd -- "$candidate/../../../.." && pwd)}
shared="$project/reconstruction/plugins/effects"
work="$project/.tools/plugin-work/effects/fast-dist-host-delegated-public/negative-wrong-count"
mkdir -p "$work/VL Host Dist"
clang++ -std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log -Wall -Wextra -Werror -dynamiclib -I "$shared" -I "$candidate" "$candidate/host_delegated_wrong_count.cpp" -o "$work/VL Host Dist/VL Host Dist_X64.dylib"
set +e
"$project/.tools/plugin-work/effects/fast-dist-host-delegated-public/canonical-normal/test_host" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Fast Dist/Fruity Fast Dist_x64.dylib' "$work/VL Host Dist/VL Host Dist_X64.dylib" "$work/VL Host Dist/VL Host Dist.dylib" "$work/" > "$work/stdout.log" 2> "$work/stderr.log"
code=$?
set -e
python3 - "$work" "$code" <<'PY_CHECK'
from pathlib import Path
import json,sys
w=Path(sys.argv[1]);code=int(sys.argv[2]);s=(w/'stderr.log').read_text();assert code==1 and s.strip() in ['Delegated native sample differs','Host callback ordinal/receiver/arguments differ'],(code,s)
assert (w/'stdout.log').read_bytes()==b''
r={'status':'expected_failure_wrong_host_count_argument','exit_code':code,'stderr':s,'mutation':'scalar sample count frames*2 -> frames; legal host signature and intact native callback/adapter retained','full_plugin_equivalence':False};(w/'result.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
PY_CHECK
