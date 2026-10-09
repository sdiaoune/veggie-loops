#!/usr/bin/env python3
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python assertions; unset PYTHONOPTIMIZE and omit -O.")
import hashlib,json,pathlib,sys,struct
if len(sys.argv)!=3:raise SystemExit(2)
source=pathlib.Path(sys.argv[1]);work=pathlib.Path(sys.argv[2])
def sha(p):
 h=hashlib.sha256()
 with p.open('rb')as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
def record(p):return {'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size}
def load(p):assert p.is_file(),str(p);return json.loads(p.read_text())
canonical=load(source/'verification.json')
for mode in ['normal','sanitized']:
 r=canonical['results'][mode];assert r['contract']['successes']==5 and r['contract']['atomic_rejections']==180
 assert r['native']['comparisons']==760 and r['native']['exact_owned_bytes']==7564080 and r['native']['full_fenv_restorations']==760
for name in ['xy-api.h','xy-api.cpp','xy-contract.cpp','xy-native.mm','verify.sh']:assert canonical['sources'][name]==sha(source/name)
assert len(canonical['negative_controls'])==6 and all(x['exit_code']==1 for x in canonical['negative_controls'])
endpoint=load(work/'endpoint/results.json');active=load(work/'native-active/results.json');contracts=load(work/'validation-contract/results.json');o0=load(work/'o0/results.json');negative=load(work/'validation-negative/results.json')
for mode in ['normal','sanitized']:
 r=endpoint['results'][mode];assert r['status']=='passed_effects_XY_endpoint_order_sticky' and r['cleared_native_pairs']==144 and r['inherited_native_pairs']==144 and r['full_caller_fenv_restorations']==288
 r=active['results'][mode];assert r['status']=='passed_repaired_validation_unused_fields' and r['native_pairs']==9 and r['source_validation_excess_denormal'] is False
 assert all(x['source_mask']==x['native_mask'] for x in r['pairs'])
assert endpoint['results']['normal']==endpoint['results']['sanitized'] and active['results']['normal']==active['results']['sanitized']
assert set(contracts['results'])=={'normal-arm64','normal-x86_64','sanitized-arm64','sanitized-x86_64'}
for r in contracts['results'].values():assert r['calls']==1488 and r['accepted']==488 and r['atomic_rejections']==1000 and r['full_fenv_readbacks']==1488
r=o0['result'];assert r['status']=='observed_API_O0_coordinate_evaluation_order' and r['native_pairs']==9 and r['mask_differences']==0
assert all(x['source_mask']==x['native_mask']for x in r['pairs'])
assert len(negative['results'])==4 and {x['variant']for x in negative['results']}=={'old_float_magnitude','old_float_endpoint_order','unequal_signed_zeros','late_coordinate_comparison'} and all(x['exit_code']==1 for x in negative['results'])
for p in work.rglob('*.log'):
 t=p.read_text(errors='replace');assert not any(s in t for s in ['runtime error:','AddressSanitizer','UndefinedBehaviorSanitizer']),str(p)
files=['xy-api.h','xy-api.cpp','xy-contract.cpp','xy-native.mm','verify.sh','NOTES.md','REPAIR.md','xy-effects-supplement-fenv.mm','verify-effects-supplement-fenv.sh','test_validation_native.mm','test_validation_native_active.mm','verify_validation_native_active.sh','test_validation_contract_qualified.cpp','verify_validation_contract_qualified.sh','test_validation_native_o0.mm','verify_validation_o0.sh','verify_validation_negatives.py','verify_all.sh','summarize_validation.py']
original=pathlib.Path('/Library/Audio/Plug-Ins/VST/u-he/TyrellN6.vst/Contents/MacOS/TyrellN6')
assert sha(original)=='a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54'
blob=original.read_bytes();magic,count=struct.unpack_from('>II',blob);assert magic==0xcafebabe
slices=[struct.unpack_from('>5I',blob,8+20*i)for i in range(count)]
arch=next(row for row in slices if row[0]==0x01000007);offset,length=arch[2:4]
slice_sha=hashlib.sha256(memoryview(blob)[offset:offset+length]).hexdigest();assert slice_sha=='8d76659f91ce432b1d58f835b2c6ee1bfd30ac9de61e579500d3c712b22def38'
identities=[{**record(original),'role':'intact original executed via universal x86_64 slice'},{'origin_path':str(original),'architecture':'x86_64','slice_offset':offset,'bytes':length,'sha256':slice_sha,'role':'same pinned thin bytes derived read-only from universal; no standalone thin-file execution or private-evidence runtime dependency'}]
report={'status':'builder_verified_validation_and_coordinate_order_repair_pending_two_independent_reviews','source_records':[record(source/name)for name in files],'native_identities':identities,'results':{'canonical':canonical['results'],'endpoint':endpoint['results'],'native-active':active['results'],'validation-contract':contracts['results'],'o0':o0['result']},'negatives':{'scalar':canonical['negative_controls'],'validation-order':negative['results']},'work_records':[record(p)for p in sorted(work.rglob('*'))if p.is_file()],'canonical_basis':record(source/'verification.json'),'source_and_harness_sanitized_in_fatal_mode':True,'original_image_instrumented':False,'original_patched':False,'all_original_calls_valid_fresh_clones':True,'same_native_allocation_reused':False,'independent_acceptance':False,'natural_active_XY':False,'positive_queue':False,'arbitrary_FP_traps_or_compiler_codegen':False,'audio_scheduler_editor_RT_full_plugin_equivalence':False}
(source/'repaired-verification.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'status':report['status'],'source_files':len(files),'O0_mask_differences':r['mask_differences'],'original_patched':False}))
