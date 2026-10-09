#!/bin/sh
set -eu
own=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=${VL_BALANCE_PROTOCOL_ROOT:-$(CDPATH= cd -- "$own/../../../.." && pwd)}
shared="$root/reconstruction/plugins/effects"
work=${VL_BALANCE_PROTOCOL_EDITOR_WORK:-"$root/.tools/plugin-work/effects/balance-public-protocol/editor-regression"}
python3 "$own/verify_manifest.py"
for mode in normal sanitized; do
 dst="$work/$mode";mkdir -p "$dst";flags=''
 if [ "$mode" = sanitized ]; then flags='-fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer'; fi
 clang++ -std=c++20 -O2 -fobjc-arc -DVL_BALANCE_APPKIT_EDITOR=1 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror $flags -I "$shared" -dynamiclib "$shared/balance_native_abi.cpp" "$shared/balance_plugin.cpp" "$shared/balance_editor.mm" -framework Cocoa -o "$dst/VLBalanceNativeEditor.dylib"
 clang++ -std=c++20 -O2 -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations $flags -I "$shared" "$shared/test_balance_native_editor.mm" -framework Cocoa -o "$dst/test_native_editor"
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$dst/test_native_editor" '/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib' "$dst/VLBalanceNativeEditor.dylib" > "$dst/result.json" 2> "$dst/stderr.log"
 done
python3 - "$work" <<'PY_EDITOR'
import json,sys
from pathlib import Path
p=Path(sys.argv[1]);out={}
for mode in ('normal','sanitized'):
 w=p/mode;assert not(w/'stderr.log').read_bytes();r=json.loads((w/'result.json').read_text());assert r['status']=='passed' and r['concurrent_first_attachment_worker_hints_checked'] and r['worker_tick_idle_skipped_gui'] and not r['actual_fl_application_created'] and not r['full_plugin_equivalence'];out[mode]=r
(p/'results.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'status':'passed_existing_optional_editor_regression','modes':list(out),'full_plugin_equivalence':False}))
PY_EDITOR
