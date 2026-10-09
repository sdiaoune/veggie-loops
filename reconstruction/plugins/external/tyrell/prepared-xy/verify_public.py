#!/usr/bin/env python3
"""Reproduce the bounded native comparison in an isolated source copy."""
import hashlib,json,os,pathlib,shutil,subprocess,tempfile
own=pathlib.Path(__file__).resolve().parent;root=own.parents[4]
manifest=json.loads((own/'publication-manifest.json').read_text())
for r in manifest['sources']:
 p=root/r['path'];assert p.is_file() and hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256'],p
requested=os.environ.get('VL_TYRELL_XY_PUBLIC_WORK')
if requested:
 work=pathlib.Path(requested).resolve();work.mkdir(parents=True,exist_ok=False)
else:
 parent=root/'.tools/plugin-work/external/tyrell';parent.mkdir(parents=True,exist_ok=True)
 work=pathlib.Path(tempfile.mkdtemp(prefix='prepared-xy-public-',dir=parent))
project=work/'project'
for r in manifest['sources']:
 src=root/r['path'];dst=project/r['path'];dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
 assert hashlib.sha256(dst.read_bytes()).hexdigest()==r['sha256']
source=project/own.relative_to(root);env=dict(os.environ,VL_TYRELL_XY_REPAIR_WORK_DIR=str(work/'results'))
with (work/'replay.stdout').open('wb') as o,(work/'replay.stderr').open('wb') as e:
 result=subprocess.run(['sh',str(source/'verify_all.sh')],stdout=o,stderr=e,env=env)
assert result.returncode==0, f'Replay failed with {result.returncode}; preserved logs: {work}'
assert (work/'replay.stderr').read_bytes()==b'',f'Observer diagnostics: {work}'
for r in manifest['sources']:
 assert hashlib.sha256((root/r['path']).read_bytes()).hexdigest()==r['sha256'],r['path']
print(json.dumps({'status':'bounded_prepared_XY_public_recipe_passed','work':str(work),'full_plugin_equivalence':False}))
