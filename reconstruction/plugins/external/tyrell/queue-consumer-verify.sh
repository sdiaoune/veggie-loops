#!/bin/sh
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$source_dir/../../../.." && pwd)
work_dir=${1:-"$project_root/.tools/plugin-work/external/tyrell/queue-consumer-public-check"}
if [ "$#" -gt 1 ]; then exit 2; fi
mkdir -p "$work_dir"
flags='-std=c++20 -O2 -fno-fast-math -ffp-contract=off -Wall -Wextra -Werror -fsanitize=address,undefined,float-cast-overflow -fno-sanitize-recover=all -fno-omit-frame-pointer'
for architecture in arm64 x86_64; do
 clang++ -arch "$architecture" $flags "$source_dir/queue-consumer-storage.cpp" \
  "$source_dir/queue-consumer-contract.cpp" -o "$work_dir/queue-consumer-contract-$architecture"
 if [ "$architecture" = x86_64 ]; then
  codesign --force --sign - "$work_dir/queue-consumer-contract-$architecture"
  codesign --verify --strict "$work_dir/queue-consumer-contract-$architecture"
 fi
 ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
  "$work_dir/queue-consumer-contract-$architecture" > "$work_dir/contract-$architecture.log" 2>&1
done
clang++ -arch x86_64 $flags -dynamiclib "$source_dir/queue-consumer-storage.cpp" \
 -Wl,-install_name,@rpath/libVLTyrellQueue.dylib -o "$work_dir/libVLTyrellQueue.dylib"
clang++ -arch x86_64 $flags -fno-builtin-floorf -Wno-deprecated-declarations -framework Cocoa \
 "$source_dir/queue-consumer-native.mm" -L "$work_dir" -lVLTyrellQueue -Wl,-rpath,@loader_path \
 -o "$work_dir/queue-consumer-native"
for artifact in libVLTyrellQueue.dylib queue-consumer-native; do
 codesign --force --sign - "$work_dir/$artifact"
 codesign --verify --strict "$work_dir/$artifact"
done
ASAN_OPTIONS=halt_on_error=1 UBSAN_OPTIONS=halt_on_error=1 \
 "$work_dir/queue-consumer-native" '/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst' > "$work_dir/native.log" 2>&1
python3 - "$source_dir" "$work_dir" <<'PY'
import hashlib,json,pathlib,subprocess,sys,shutil,os
source,work=map(pathlib.Path,sys.argv[1:]);flags=['-arch','x86_64','-std=c++20','-O2','-fno-fast-math','-ffp-contract=off','-Wall','-Wextra','-Werror','-fsanitize=address,undefined,float-cast-overflow','-fno-sanitize-recover=all','-fno-omit-frame-pointer']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def result(p,status):
 text=p.read_text();assert not any(x in text for x in ['runtime error:','Sanitizer','UndefinedBehavior'])
 rows=[json.loads(x) for x in text.splitlines() if x.startswith('{')];assert len(rows)==1 and rows[0]['status']==status;return rows[0]
contracts={arch:result(work/f'contract-{arch}.log','passed_queue_consumer_contract') for arch in ['arm64','x86_64']};assert contracts['arm64']==contracts['x86_64']
native=result(work/'native.log','passed_original_queue_consumer')
assert native['direct_calls']==17290 and native['captured_restores']==17290 and native['ordinary_render_calls']==6609 and native['completion_checks']==118
text=(source/'queue-consumer-storage.cpp').read_text()
mutations={
 'wrong-decrement':('record.remaining=old-1;','record.remaining=old-2;'),
 'forward-copy':('for(uint32_t i=visited;i>0;--i){const int32_t id=next.changed[i-1];','for(uint32_t i=0;i<visited;++i){const int32_t id=next.changed[i];'),
 'wrong-cyclic-range':('range=d[id].maximum-d[id].minimum;','range=d[id].maximum;'),
 'skip-revisit':('if(index<next.queue_count)next.queue[index]=next.queue[next.queue_count];','if(index<next.queue_count)next.queue[index]=next.queue[next.queue_count];++index;'),
}
negative=[]
for name,(before,after) in mutations.items():
 assert text.count(before)==1;directory=work/('negative-'+name);directory.mkdir(exist_ok=True)
 mutant=directory/'queue-consumer-storage-mutant.cpp';mutant.write_text(text.replace(before,after));shutil.copy2(source/'queue-consumer-storage.h',directory/'queue-consumer-storage.h')
 subprocess.run(['clang++',*flags,'-dynamiclib',str(mutant),'-Wl,-install_name,@rpath/libVLTyrellQueue.dylib','-o',str(directory/'libVLTyrellQueue.dylib')],check=True)
 shutil.copy2(work/'queue-consumer-native',directory/'queue-consumer-native')
 for artifact in ['libVLTyrellQueue.dylib','queue-consumer-native']:
  subprocess.run(['codesign','--force','--sign','-',str(directory/artifact)],check=True)
  subprocess.run(['codesign','--verify','--strict',str(directory/artifact)],check=True)
 env=dict(os.environ,ASAN_OPTIONS='halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
 with (directory/'native.log').open('w') as log:
  p=subprocess.run([str(directory/'queue-consumer-native'),'/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst'],stdout=log,stderr=subprocess.STDOUT,env=env)
 diagnostic=(directory/'native.log').read_text();assert p.returncode==1 and 'Consumer scalar snapshot differs' in diagnostic and 'passed_original_queue_consumer' not in diagnostic
 assert not any(x in diagnostic for x in ['runtime error:','Sanitizer','UndefinedBehavior'])
 negative.append({'name':name,'exit_code':p.returncode,'failure':'Consumer scalar snapshot differs','source_sha256':sha(mutant),'log_sha256':sha(directory/'native.log'),'original_code_or_callbacks_mutated':False})
files=['queue-consumer-storage.h','queue-consumer-storage.cpp','queue-consumer-contract.cpp','queue-consumer-native.mm','queue-consumer-verify.sh','QUEUE_CONSUMER.md']
report={'status':'builder_verified_no_XY_queue_consumer_pending_independent_review','source_sha256':{f:sha(source/f) for f in files},'contracts':contracts,'native':native,'negative_controls':negative,'logs_sha256':{f:sha(work/f) for f in ['contract-arm64.log','contract-x86_64.log','native.log']},'artifacts_sha256':{f:sha(work/f) for f in ['queue-consumer-contract-arm64','queue-consumer-contract-x86_64','libVLTyrellQueue.dylib','queue-consumer-native']},'fatal_sanitizers':True,'owned_Intel_artifacts_signed_verified':True,'full_plugin_equivalence':False}
(work/'verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'contracts':contracts,'native':native,'negative_controls':negative},indent=2))
PY
