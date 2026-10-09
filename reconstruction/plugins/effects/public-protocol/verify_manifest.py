import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python assertions; unset PYTHONOPTIMIZE and omit -O.")
from pathlib import Path
import hashlib,json
own=Path(__file__).resolve().parent;root=own.parents[3]
manifest=json.loads((own/'verification.json').read_text())
for record in manifest['source_closure']:
 p=root/record['path'];assert p.is_file(),record['path'];assert hashlib.sha256(p.read_bytes()).hexdigest()==record['sha256'],record['path']
for record in manifest['original_targets']:
 p=Path(record['path']);assert p.is_file(),record['path'];assert hashlib.sha256(p.read_bytes()).hexdigest()==record['sha256'],record['path']
assert manifest['full_plugin_equivalence'] is False and manifest['original_extra_destructor_equivalence'] is False
print(json.dumps({'status':'public_protocol_source_and_target_manifest_verified','source_files':len(manifest['source_closure']),'original_targets':len(manifest['original_targets']),'full_plugin_equivalence':False}))
