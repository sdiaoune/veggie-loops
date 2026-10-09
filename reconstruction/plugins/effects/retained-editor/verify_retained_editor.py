#!/usr/bin/env python3
"""Verify own retained-editor teardown against the published source closure."""
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python assertions; unset PYTHONOPTIMIZE and omit -O.")
import argparse, hashlib, json, os, pathlib, subprocess
p=argparse.ArgumentParser();p.add_argument('work',type=pathlib.Path);a=p.parse_args()
own=pathlib.Path(__file__).resolve().parent;shared=own.parent;work=a.work.resolve();work.mkdir(parents=True,exist_ok=False)
manifest=json.loads((own/'verification.json').read_text())
for row in manifest['sources']:
 f=shared/row['path'];assert hashlib.sha256(f.read_bytes()).hexdigest()==row['sha256'], f
base=['clang++','-std=c++20','-Wall','-Wextra','-Werror','-fno-fast-math','-ffp-contract=off','-fobjc-arc','-DVL_BALANCE_APPKIT_EDITOR=1','-framework','Cocoa','-I',str(shared)]
rows=[]
def sign_verify(exe,out):
 for name,cmd in [('sign',['codesign','--force','--sign','-',str(exe)]),('strict-signature',['codesign','--verify','--strict',str(exe)])]:
  with (out/(name+'.stdout')).open('wb') as o,(out/(name+'.stderr')).open('wb') as e:subprocess.run(cmd,stdout=o,stderr=e,check=True)
def require_empty(out,names):
 for name in names:assert (out/name).read_bytes()==b'',str(out/name)+' contains diagnostics'
for mode in ['normal','sanitized','O0']:
 out=work/mode;out.mkdir();flags=['-O0' if mode=='O0' else '-O2']
 if mode=='sanitized':flags+=['-fsanitize=address,undefined,float-cast-overflow','-fno-sanitize-recover=all','-fno-omit-frame-pointer']
 exe=out/'test_retained_editor';cmd=base+flags+[str(own/'test_retained_editor.mm'),str(shared/'balance_plugin.cpp'),'-o',str(exe)]
 with (out/'compile.stdout').open('wb') as o,(out/'compile.stderr').open('wb') as e:subprocess.run(cmd,stdout=o,stderr=e,check=True)
 require_empty(out,['compile.stdout','compile.stderr'])
 sign_verify(exe,out)
 env=dict(os.environ,ASAN_OPTIONS='halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
 with (out/'result.json').open('wb') as o,(out/'runtime.stderr').open('wb') as e:subprocess.run([str(exe)],stdout=o,stderr=e,env=env,check=True)
 require_empty(out,['runtime.stderr'])
 result=json.loads((out/'result.json').read_text());assert result=={'status':'matched_own_retained_editor_teardown_contract','instances':144,'subject_routes':72,'off_main_attached_refusals':72,'retained_actions':432,'live_peer_actions':216,'original_editor_compared':False,'full_plugin_equivalence':False}
 rows.append({'mode':mode,'exit':0,'result':result})
mutants=[('retained-host','  view.callbacks={};\n',''),('retained-targets','  for(NSControl* control in view.sliders)control.target=nil;\n',''),('retained-numerical','view.numerical=nullptr;','')]
for name,before,after in mutants:
 out=work/name;out.mkdir();source=(shared/'balance_editor.mm').read_text();assert source.count(before)==1
 (out/'balance_editor.mm').write_text(source.replace(before,after));fixture=(own/'test_retained_editor.mm').read_text().replace('#include "../balance_native_abi.cpp"','#include "'+str(shared/'balance_native_abi.cpp')+'"').replace('#include "../balance_editor.mm"','#include "balance_editor.mm"')
 (out/'test_retained_editor.mm').write_text(fixture)
 exe=out/'negative';flags=['-O2','-fsanitize=address,undefined,float-cast-overflow','-fno-sanitize-recover=all','-fno-omit-frame-pointer']
 with (out/'compile.stdout').open('wb') as o,(out/'compile.stderr').open('wb') as e:subprocess.run(base+flags+[str(out/'test_retained_editor.mm'),str(shared/'balance_plugin.cpp'),'-o',str(exe)],stdout=o,stderr=e,check=True)
 require_empty(out,['compile.stdout','compile.stderr'])
 sign_verify(exe,out)
 with (out/'runtime.stdout').open('wb') as o,(out/'runtime.stderr').open('wb') as e:r=subprocess.run([str(exe)],stdout=o,stderr=e,env=env)
 expected={'retained-host':'Retained editor preserves host callback or context','retained-targets':'Retained control preserves action target','retained-numerical':'Retained view still owns numerical storage or parent'}[name]
 text=(out/'runtime.stderr').read_text();assert r.returncode==1 and expected in text and 'ERROR: AddressSanitizer' not in text and 'runtime error:' not in text,(name,r.returncode,text)
 rows.append({'negative':name,'exit':r.returncode,'rejected_before_ended_instance_access':True})
for row in manifest['sources']:assert hashlib.sha256((shared/row['path']).read_bytes()).hexdigest()==row['sha256']
artifacts=[{'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'bytes':f.stat().st_size} for f in sorted(work.rglob('*')) if f.is_file()]
report={'status':'own_source_retained_editor_contract_passed','candidate_manifest_sha256':hashlib.sha256((own/'verification.json').read_bytes()).hexdigest(),'runs':rows,'artifacts':artifacts,'original_editor_compared':False,'full_plugin_equivalence':False}
(work/'verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'report':str(work/'verification.json')}))
