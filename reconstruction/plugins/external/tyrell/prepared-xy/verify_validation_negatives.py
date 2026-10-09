#!/usr/bin/env python3
import hashlib,json,os,pathlib,subprocess,sys
source=pathlib.Path(__file__).resolve().parent
if len(sys.argv)!=2:raise SystemExit(2)
work=pathlib.Path(sys.argv[1]);work.mkdir(parents=True,exist_ok=True)
text=(source/'xy-api.cpp').read_text()
before='return (std::bit_cast<uint32_t>(x)&0x7fffffffu)<=std::bit_cast<uint32_t>(limit);'
order='''bool finiteGreater(float left,float right) {
 const uint32_t a=std::bit_cast<uint32_t>(left),b=std::bit_cast<uint32_t>(right);
 if(((a|b)&0x7fffffffu)==0)return false; // Both signed zeros compare equal.
 const uint32_t ka=(a&0x80000000u)?~a:(a^0x80000000u);
 const uint32_t kb=(b&0x80000000u)?~b:(b^0x80000000u);
 return ka>kb;
}'''
zero='if(((a|b)&0x7fffffffu)==0)return false; // Both signed zeros compare equal.'
variants=[('old_float_magnitude',before,'return std::isfinite(x)&&std::fabs(x)<=limit;','native'),('old_float_endpoint_order',order,'bool finiteGreater(float left,float right) { return left>right; }','native'),('unequal_signed_zeros',zero,'// Reviewer-only wrong signed-zero ordering.','source'),('late_coordinate_comparison','const bool positive=coordinate>0; // Original evaluates this before target skipping.','// Reviewer-only late comparison.','native-active')]
flags=['-arch','x86_64','-std=c++20','-O2','-fno-fast-math','-ffp-contract=off','-Wall','-Wextra','-Werror','-fsanitize=address,undefined,float-cast-overflow','-fno-sanitize-recover=all','-fno-omit-frame-pointer']
results=[]
for name,before,after,route in variants:
 assert text.count(before)==1;directory=work/name;directory.mkdir(exist_ok=True);cpp=directory/'xy-api-wrong.cpp';mutant=text.replace(before,after)
 if name=='late_coordinate_comparison':
  marker='if(id<0)continue;';assert mutant.count(marker)==1;mutant=mutant.replace(marker,marker+'const bool positive=coordinate>0;')
 cpp.write_text(mutant);(directory/'xy-api.h').write_bytes((source/'xy-api.h').read_bytes())
 if route.startswith('native'):
  lib=directory/'libVLTyrellXY.dylib';exe=directory/'native-wrong';subprocess.run(['clang++',*flags,'-dynamiclib',str(cpp),'-Wl,-install_name,@rpath/libVLTyrellXY.dylib','-o',str(lib)],check=True)
  subprocess.run(['clang++',*flags,'-Wno-deprecated-declarations','-Wno-unused-function','-Wno-unused-variable','-framework','Cocoa',str(source/('test_validation_native_active.mm'if route=='native-active'else 'test_validation_native.mm')),'-L',str(directory),'-lVLTyrellXY','-Wl,-rpath,@loader_path','-o',str(exe)],check=True);artifacts=[lib,exe];args=[str(exe),'/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst'];message='Repaired validation or active-coordinate native FE status differs'if route=='native-active'else 'Repaired validation still alters unused-field FE status'
 else:
  exe=directory/'contract-wrong';subprocess.run(['clang++',*flags,str(cpp),str(source/'test_validation_contract_qualified.cpp'),'-o',str(exe)],check=True);artifacts=[exe];args=[str(exe)];message='Validation acceptance differs from ordinary finite reference'
 for artifact in artifacts:
  with (directory/(artifact.name+'-sign.log')).open('w')as log:
   subprocess.run(['codesign','--force','--sign','-',str(artifact)],stdout=log,stderr=subprocess.STDOUT,check=True);subprocess.run(['codesign','--verify','--strict',str(artifact)],stdout=log,stderr=subprocess.STDOUT,check=True)
 env=dict(os.environ,ASAN_OPTIONS='halt_on_error=1',UBSAN_OPTIONS='halt_on_error=1')
 with (directory/'results.log').open('w')as log:run=subprocess.run(args,stdout=log,stderr=subprocess.STDOUT,env=env)
 output=(directory/'results.log').read_text();assert run.returncode==1 and message in output,name
 assert not any(s in output for s in ['runtime error:','Sanitizer','UndefinedBehavior']),name
 results.append({'variant':name,'route':route,'exit_code':run.returncode,'expected_failure':message,'original_patched':False,'wrong_source_sha256':hashlib.sha256(cpp.read_bytes()).hexdigest()})
report={'status':'builder_four_validation_and_order_mutants_rejected','results':results,'source_and_fixture_sanitized':True,'original_instrumented':False,'records':[{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}for p in work.rglob('*')if p.is_file()],'full_plugin_equivalence':False}
(work/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(results,indent=2))
