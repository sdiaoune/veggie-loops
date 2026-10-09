import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python assertions; unset PYTHONOPTIMIZE and omit -O.")
from pathlib import Path
import subprocess,os,json,hashlib
own=Path(__file__).resolve().parent;root=Path(os.environ.get('VL_BALANCE_PROTOCOL_ROOT',own.parents[3]));shared=root/'reconstruction/plugins/effects';work=Path(os.environ.get('VL_BALANCE_PROTOCOL_NEGATIVE_WORK',root/'.tools/plugin-work/effects/balance-public-protocol/negative-work'));work.mkdir(parents=True,exist_ok=True)
subprocess.run(['python3',str(own/'verify_manifest.py')],check=True)
positiveWork=Path(os.environ.get('VL_BALANCE_PROTOCOL_WORK',root/'.tools/plugin-work/effects/balance-public-protocol/work'))
base=(shared/'balance_native_abi.cpp').read_text()
cases=[('old_names','"^b^aBalance":"^b^aVolume"','"Pan":"Volume"','Native/source name buffer differs','protocol'),('clear_other_sections','if(!output || section!=0 || index<0 || index>1)return;','if(!output || index<0 || index>1)return;\n  if(section!=0){output[0]=0;return;}','Native/source name buffer differs','protocol'),('ignore_max_poly','if(id==1)instance(p).maxPoly=value;','(void)p;(void)id;(void)value;','Native/source maximum-polyphony state differs','protocol'),('write_MonoRender','if(id==1)instance(p).maxPoly=value;','if(id==1){instance(p).maxPoly=value;p->mono=value;}','Source MonoRender unexpectedly changed','protocol'),('complete_deallocates','void completeDestructor(Plugin* p){(void)finishLifetime(p);}','void completeDestructor(Plugin* p){if(finishLifetime(p))::operator delete(static_cast<void*>(p));}','Complete destructor must clean ownership without deallocation','lifetime'),('omit_numerical_cleanup','vl_balance_destroy(object->numerical);','/* deliberately wrong: numerical ownership leaked */','Complete destructor must clean ownership without deallocation','lifetime')]
common=['clang++','-std=c++20','-O2','-fno-fast-math','-ffp-contract=off','-Wall','-Wextra','-Werror','-I',str(shared)];results=[]
for name,old,new,expected,kind in cases:
 assert base.count(old)==1,name;dst=work/name;dst.mkdir(exist_ok=True);(dst/'balance_native_abi.cpp').write_text(base.replace(old,new))
 if kind=='protocol':
  (dst/'protocol_probe.cpp').write_text((own/'protocol_probe.cpp').read_text().replace('#include "../balance_native_abi.cpp"','#include "balance_native_abi.cpp"'));subprocess.run(common+['-dynamiclib',str(dst/'protocol_probe.cpp'),str(shared/'balance_plugin.cpp'),'-o',str(dst/'mutant.dylib')],check=True)
  command=[str(positiveWork/'normal/test_protocol'),'/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Effects/Fruity Balance/Fruity Balance_x64.dylib',str(dst)+'/',str(dst/'mutant.dylib')]
 else:
  (dst/'test_lifetime.cpp').write_text((own/'test_lifetime.cpp').read_text().replace('#include "../balance_native_abi.cpp"','#include "balance_native_abi.cpp"'));subprocess.run(common+[str(dst/'test_lifetime.cpp'),str(shared/'balance_plugin.cpp'),'-o',str(dst/'test_lifetime')],check=True);command=[str(dst/'test_lifetime')]
 result=subprocess.run(command,capture_output=True);(dst/'stdout.log').write_bytes(result.stdout);(dst/'stderr.log').write_bytes(result.stderr);assert result.returncode!=0 and expected in result.stderr.decode(),(name,result.returncode,result.stderr);results.append({'name':name,'exit_code':result.returncode,'rejected_by':expected,'mutant_source_sha256':hashlib.sha256((dst/'balance_native_abi.cpp').read_bytes()).hexdigest(),'kind':kind})
assert (shared/'balance_native_abi.cpp').read_text()==base
out={'status':'all_six_semantic_mutants_rejected','results':results,'installed_original_bytes_changed':False,'accepted_candidate_changed':False,'full_plugin_equivalence':False};(work/'results.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out))
