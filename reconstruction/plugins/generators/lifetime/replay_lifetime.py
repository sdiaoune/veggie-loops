"""Prepared source-only recipe; no execution until a fresh root serial-slot grant."""
import sys
if sys.flags.optimize:
 raise SystemExit("Optimized Python is unsupported: verification assertions must remain enabled")
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess
p=argparse.ArgumentParser();p.add_argument('phase',choices=['source']);p.add_argument('--work',type=Path);a=p.parse_args()
assert os.environ.get('VL_SOURCE_LIFETIME_SLOT_GRANTED')=='1','Root serial compiler/source-execution slot required'
own=Path(__file__).resolve().parent;root=own.parents[3]
source=root/'reconstruction/plugins/generators';immediate=source/'live-context';prevoice=root/'.tools/plugin-work/generators/prevoice-preparation-repair'
work=(a.work or own/'work').resolve();work.mkdir(parents=True,exist_ok=False)
manifest=json.loads((own/'candidate-source.json').read_text())
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def check_inputs():
 for r in manifest['owned_sources']+manifest['external_compilation_closure']:
  path=own/r['name'] if 'name' in r else root/r['path'];assert sha(path)==r['sha256'],str(path)+' changed'
check_inputs()
base=['clang++','-arch','arm64','-std=c++20','-Wall','-Wextra','-Werror','-fno-fast-math','-ffp-contract=off','-I',str(source),'-I',str(immediate),'-I',str(prevoice),'-framework','Accelerate']
fatal=['-fsanitize=address,undefined,float-cast-overflow','-fno-sanitize-recover=all','-fno-omit-frame-pointer']
env=dict(os.environ,ASAN_OPTIONS='halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
common=[source/n for n in ['three_osc_sync_lfo.cpp','three_osc_voice_lifecycle.cpp','three_osc_declick.cpp','three_osc_engine.cpp','three_osc_legacy_tables.cpp']]
variants=[('stock',0,'stock_factory.cpp',source/'three_osc_multimode_channel.cpp'),('immediate',1,'immediate_factory.cpp',immediate/'immediate_channel.cpp'),('prevoice',2,'prevoice_factory.cpp',prevoice/'prevoice_channel.cpp')]
def compile_fixture(directory,mode,variant,fixture):
 name,index,cpp,channel=variant
 command=base+(['-O0'] if mode=='O0' else ['-O2'])+(fatal if mode=='sanitized' else [])+['-DVL_LIFETIME_VARIANT='+str(index),str(fixture),str(channel)]
 # The prevoice factory includes the exact core.cpp once. Other factories link it once.
 if name!='prevoice':command+=[str(source/'three_osc_wrapper_core.cpp')]
 command+=[str(f) for f in common]+['-o',str(directory/'test_lifetime')]
 with (directory/'compile.stdout').open('wb') as o,(directory/'compile.stderr').open('wb') as e:subprocess.run(command,stdout=o,stderr=e,check=True)
 assert not (directory/'compile.stdout').read_bytes() and not (directory/'compile.stderr').read_bytes()
 for stem,cmd in [('sign',['codesign','--force','--sign','-',str(directory/'test_lifetime')]),('signature',['codesign','--verify','--strict',str(directory/'test_lifetime')])]:
  with (directory/(stem+'.stdout')).open('wb') as o,(directory/(stem+'.stderr')).open('wb') as e:subprocess.run(cmd,stdout=o,stderr=e,check=True)
 assert subprocess.check_output(['lipo','-archs',str(directory/'test_lifetime')],text=True).strip()=='arm64'
 return directory/'test_lifetime'
results=[]
for mode in ['normal','sanitized','O0']:
 for variant in variants:
  name,index,cpp,channel=variant;d=work/mode/name;d.mkdir(parents=True)
  exe=compile_fixture(d,mode,variant,own/'test_lifetime.cpp')
  with (d/'result.json').open('wb') as o,(d/'runtime.stderr').open('wb') as e:subprocess.run([str(exe)],stdout=o,stderr=e,check=True,env=env)
  assert not (d/'runtime.stderr').read_bytes()
  value=json.loads((d/'result.json').read_text());expected={'status':'passed_own_three_osc_factory_lifetime','variant':index,'pairs':6,'source_instances':18,'complete_caller_free':2,'deleting':2,'DestroyObject':2,'live_subjects':3,'allocation_failures':2,'exact_peer_reference_audio_floats':3072,'Cxx_allocation_graph_restored':True,'original_images_loaded':False,'original_extra_destructor_equivalence':False,'full_plugin_equivalence':False}
  assert value==expected,(name,mode,value);results.append({'variant':name,'mode':mode,'result':value})
mutants=[('complete-frees','void completeDestructor(Plugin*p){(void)finishLifetime(p);}','void completeDestructor(Plugin*p){if(finishLifetime(p))::operator delete(static_cast<void*>(p));}','Complete destructor deallocated caller storage'),('deleting-retains','void deletingDestructor(Plugin*p){destroy(p);}','void deletingDestructor(Plugin*p){(void)finishLifetime(p);}','Deleting destructor did not deallocate storage'),('storage-leak','if(storage)vl_osc_core_destroy(storage);','','Owned storage core was not cleaned exactly once'),('channel-leak','if(channel)vl_osc_multimode_channel_destroy(channel);','','Owned channel table or voice was not cleaned exactly once')]
negative=[]
for variant in variants:
 name,index,cpp,channel=variant
 for label,before,after,message in mutants:
  d=work/'mutants'/name/label;d.mkdir(parents=True)
  text=(own/cpp).read_text();assert text.count(before)==1;(d/cpp).write_text(text.replace(before,after));shutil.copy2(own/'test_lifetime.cpp',d/'test_lifetime.cpp')
  exe=compile_fixture(d,'sanitized',variant,d/'test_lifetime.cpp')
  with (d/'stdout').open('wb') as o,(d/'stderr').open('wb') as e:r=subprocess.run([str(exe)],stdout=o,stderr=e,env=env)
  text=(d/'stderr').read_text();assert r.returncode==1 and not (d/'stdout').read_bytes() and message in text
  assert not any(n in text for n in ['Sanitizer','runtime error:','UndefinedBehavior'])
  negative.append({'variant':name,'mutant':label,'exit':1,'diagnostic':text,'rejected_before_invalid_post_lifetime_access':True})
check_inputs()
artifacts=[{'path':str(f),'sha256':sha(f),'size':f.stat().st_size} for f in sorted(work.rglob('*')) if f.is_file()]
report={'status':'passed_source_only_three_factory_lifetime_and_mutants','candidate_map_sha256':sha(own/'candidate-source.json'),'positive_runs':results,'negative_runs':negative,'artifacts':artifacts,'original_images_loaded':False,'original_extra_destructor_equivalence':False,'whole_plugin_equivalence':False}
(work/'verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'report':str(work/'verification.json')}))
