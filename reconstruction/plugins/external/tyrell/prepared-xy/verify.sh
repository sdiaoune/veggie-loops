#!/bin/sh
set -eu
python3 -c 'import sys; sys.exit("Verification requires Python assertions; unset PYTHONOPTIMIZE and omit -O.") if sys.flags.optimize else None'
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work_dir=${VL_TYRELL_XY_WORK_DIR:-"$source_dir/canonical"}
if [ "$#" -ne 0 ]; then exit 2; fi
mkdir -p "$work_dir"
for mode in normal sanitized; do
 directory="$work_dir/$mode"
 mkdir -p "$directory"
 flags='-std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror'
 if [ "$mode" = sanitized ]; then
  flags="$flags -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer"
 fi
 for architecture in arm64 x86_64; do
  clang++ -arch "$architecture" $flags "$source_dir/xy-api.cpp" "$source_dir/xy-contract.cpp" -o "$directory/contract-$architecture"
  if [ "$architecture" = x86_64 ]; then
   codesign --force --sign - "$directory/contract-$architecture" > "$directory/sign-contract-x86_64.log" 2>&1
   codesign --verify --strict "$directory/contract-$architecture" >> "$directory/sign-contract-x86_64.log" 2>&1
  fi
  ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$directory/contract-$architecture" > "$directory/contract-$architecture.log" 2>&1
 done
 clang++ -arch x86_64 $flags -dynamiclib "$source_dir/xy-api.cpp" -Wl,-install_name,@rpath/libVLTyrellXY.dylib -o "$directory/libVLTyrellXY.dylib"
 clang++ -arch x86_64 $flags -Wno-deprecated-declarations -framework Cocoa "$source_dir/xy-native.mm" -L "$directory" -lVLTyrellXY -Wl,-rpath,@loader_path -o "$directory/xy-native"
 for artifact in libVLTyrellXY.dylib xy-native; do
  codesign --force --sign - "$directory/$artifact" > "$directory/sign-$artifact.log" 2>&1
  codesign --verify --strict "$directory/$artifact" >> "$directory/sign-$artifact.log" 2>&1
 done
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 "$directory/xy-native" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst' > "$directory/native.log" 2>&1
done
python3 - "$source_dir" "$work_dir" <<'PY'
import hashlib,json,os,pathlib,shutil,subprocess,sys
source,work=map(pathlib.Path,sys.argv[1:]);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def parse(p,status):
 text=p.read_text();assert not any(x in text for x in ['runtime error:','Sanitizer','UndefinedBehavior'])
 rows=[json.loads(x) for x in text.splitlines() if x.startswith('{')];assert len(rows)==1 and rows[0]['status']==status;return rows[0]
results={}
for mode in ['normal','sanitized']:
 d=work/mode;contracts={arch:parse(d/f'contract-{arch}.log','passed_prepared_XY_contract')for arch in ['arm64','x86_64']};assert contracts['arm64']==contracts['x86_64'];native=parse(d/'native.log','passed_prepared_XY_original');assert native['comparisons']==760 and native['exact_owned_bytes']==7564080 and native['full_fenv_restorations']==760 and native['selected_original_preservation_checks']==760
 assert native['aliased_fixtures']==380 and native['packed_pointer_fixtures']==560 and native['64_touch_fixtures']==24
 results[mode]={'contract':contracts['arm64'],'native':native}
assert results['normal']==results['sanitized']
text=(source/'xy-api.cpp').read_text()
mutations={
 'wrong-depth':('record.positive_depth*coordinate','record.negative_depth*coordinate'),
 'wrong-factor':('contribution=product*0.01f','contribution=product*0.02f'),
 'deduplicated-contributions':('uint32_t touchedCount=0;','uint32_t touchedCount=0;bool seen[213]{};'),
 'wrong-fulltype':('d[id].full_type==2','(d[id].full_type&255)==2'),
 'wrong-clamp-order':('const float first=lower+d[id].maximum;\n  const float second=first+d[id].minimum;','const float first=lower+d[id].minimum;\n  const float second=first+d[id].maximum;'),
 'unique-scratch-count':('const VLTyrellXYResult result{touchedCount};','uint32_t unique=0;bool seen[213]{};for(uint32_t i=0;i<touchedCount;++i)if(!seen[next.touched[i]]){seen[next.touched[i]]=true;++unique;}const VLTyrellXYResult result{unique};'),
}
flags=['-arch','x86_64','-std=c++20','-O2','-fno-fast-math','-ffp-contract=off','-Wall','-Wextra','-Werror','-fsanitize=address,undefined,float-cast-overflow','-fno-sanitize-recover=all','-fno-omit-frame-pointer']
negative=[]
for name,(before,after) in mutations.items():
 assert text.count(before)==1;directory=work/name;directory.mkdir(exist_ok=True);mutant=text.replace(before,after)
 if name=='deduplicated-contributions':
  before='if(id<0)continue;';assert mutant.count(before)==1;mutant=mutant.replace(before,'if(id<0)continue;if(seen[id])continue;seen[id]=true;')
 p=directory/'xy-api-mutant.cpp';p.write_text(mutant);shutil.copy2(source/'xy-api.h',directory/'xy-api.h');subprocess.run(['clang++',*flags,'-dynamiclib',str(p),'-Wl,-install_name,@rpath/libVLTyrellXY.dylib','-o',str(directory/'libVLTyrellXY.dylib')],check=True);shutil.copy2(work/'sanitized/xy-native',directory/'xy-native')
 for f in ['libVLTyrellXY.dylib','xy-native']:
  subprocess.run(['codesign','--force','--sign','-',str(directory/f)],check=True);subprocess.run(['codesign','--verify','--strict',str(directory/f)],check=True)
 env=dict(os.environ,ASAN_OPTIONS='halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
 with (directory/'native.log').open('w')as log:run=subprocess.run([str(directory/'xy-native'),'/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst'],stdout=log,stderr=subprocess.STDOUT,env=env)
 diagnostic=(directory/'native.log').read_text();assert run.returncode==1 and 'passed_prepared_XY_original' not in diagnostic;assert not any(x in diagnostic for x in ['runtime error:','Sanitizer','UndefinedBehavior']);assert any(x in diagnostic for x in ['XY scalar/footprint differs','XY duplicate-inclusive scratch count differs','XY source rejected prepared native input','XY source acceptance/FE mask differs']),name
 negative.append({'name':name,'exit_code':run.returncode,'source_sha256':sha(p),'log_sha256':sha(directory/'native.log'),'original_code_or_callbacks_mutated':False})
records=[]
for p in work.rglob('*'):
 if p.is_file():records.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size})
report={'status':'builder_verified_prepared_empty_queue_XY_pending_independent_review','sources':{f:sha(source/f)for f in ['xy-api.h','xy-api.cpp','xy-contract.cpp','xy-native.mm','verify.sh','NOTES.md']},'results':results,'negative_controls':negative,'records':records,'original_plugin_instrumented':False,'source_library_and_harness_sanitized_in_fatal_mode':True,'owned_Intel_artifacts_signed_verified':True,'natural_active_XY':False,'positive_queue':False,'audio_parity':False,'full_plugin_equivalence':False}
(source/'verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'results':results,'negative_controls':negative},indent=2))
PY
