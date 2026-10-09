#!/usr/bin/env python3
"""Fail-closed author proof capture; independent acceptance remains external."""
import sys
if sys.flags.optimize:
    raise SystemExit("Verification requires Python optimization disabled.")
from pathlib import Path
import copy, hashlib, json, os, subprocess, sys
CAND=Path(__file__).resolve().parent
PROJECT=Path(os.environ.get('VL_PREVOICE_REPAIR_PROJECT_ROOT',str(CAND.parents[3])))
EXPECT={
 'cache':('passed_bounded_no_voice_preparation_cache',{'fixtures':16,'measured_callback_pairs':192,'mask_differences':0,'first_trigger_fixtures_with_cache_difference':0,'direct_actual_legacy_phase_consumer_cases':64}),
 'handoff':('passed_prevoice_cache_handoff',{'fixtures':96,'measured_callback_pairs':352,'exact_cached_words':142080,'voice_comparisons':1744,'borrowed_parameter_checks':208,'render_calls':768,'exact_audio_floats':300096,'last_voice_channel_recreations':16}),
 'rejections':('passed_prevoice_source_rejection_atomics',{'atomic_rejections':705,'states':2}),
 'prevoice_regression':('passed',{'prevoice_delivery_fixtures':72,'intact_TExPlugin_descriptor_routes':144,'exact_overwritten_audio_floats':225072}),
 'live_regression':('passed_live_context_variant',{'fixtures':96,'fixtures_with_audio_difference':0,'fixtures_with_first_state_difference':0}),
 'preparation':('passed_active_immediate_preparation_and_next_use',{'fixtures':16,'immediate_mask_differences':0,'full_fenv_restorations':240,'exact_prepared_words':44400,'second_voice_triggers':16,'exact_audio_floats':20352})}
BAD=['runtime error:','ERROR: AddressSanitizer','UndefinedBehaviorSanitizer','SUMMARY:','Sanitizer:DEADLYSIGNAL']
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def path(p):
 p=Path(p);return p if p.is_absolute() else PROJECT/p
def binding(p):return {'path':str(p),'sha256':sha(p),'size':p.stat().st_size}
def validate_record(name,r):
 status,counts=EXPECT[name]
 if r.get('status')!=status:raise ValueError('Failed/missing status: '+name)
 for key,value in counts.items():
  if r.get(key)!=value:raise ValueError('Count mismatch: '+name+'/'+key)
 if r.get('full_plugin_equivalence') is not False:raise ValueError('Full claim present/missing: '+name)
def collect(work,base):
 for b in base['bound_source_inputs']+base['original_images']:
  p=path(b['path'])
  if sha(p)!=b['sha256']:raise ValueError('Source/original identity differs: '+str(p))
 factory=(CAND/'prevoice_factory.cpp').read_text()
 if factory.count('#include "three_osc_wrapper_core.cpp"')!=1:raise ValueError('Core implementation must be included exactly once')
 for n in ['verify_prevoice_repair.sh','verify_prevoice_negatives.sh']:
  recipe=(CAND/n).read_text()
  if '"$source/three_osc_wrapper_core.cpp"' in recipe:raise ValueError('Duplicate core link input')
  if '-fno-sanitize-recover=all' not in recipe and n=='verify_prevoice_repair.sh':raise ValueError('Missing fatal sanitizer')
  if 'codesign --force --sign -' not in recipe:raise ValueError('Unsigned own runtime recipe')
 cases={};artifacts=[]
 for mode in ['native','sanitized','O0']:
  p=work/('canonical-'+mode);cases[mode]={}
  for name in EXPECT:
   stderr=(p/(name+'-stderr.log')).read_text()
   if stderr:raise ValueError('Unexpected canonical stderr: '+mode+'/'+name+': '+stderr)
   r=json.loads((p/(name+'-result.json')).read_text());validate_record(name,r);cases[mode][name]={k:v for k,v in r.items() if not isinstance(v,list)}
   artifacts.extend([binding(p/(name+'-result.json')),binding(p/(name+'-stderr.log'))])
  for log in p.glob('compile-*.stderr'):
   if log.read_text():raise ValueError('Compiler diagnostic: '+str(log))
   artifacts.append(binding(log))
  artifacts.append(binding(p/'VL 3 Osc/VL 3 Osc_X64.dylib'))
  for f in sorted(p.glob('test_*')):artifacts.append(binding(f))
 negatives=[]
 for name in ['no-eager','erase-history','eager-PPQ','reprepare-import','round-time']:
  p=work/'negatives'/name;r=json.loads((p/'result.json').read_text())
  if r.get('status')!='passed_expected_source_mutant_rejection' or r.get('exit')!=1:raise ValueError('Failed/missing negative: '+name)
  if (p/'stdout').read_bytes():raise ValueError('Negative emitted success: '+name)
  text=(p/'stderr').read_text()
  if not text or any(b in text for b in BAD):raise ValueError('Invalid negative diagnostic: '+name)
  if r.get('stderr')!=text:raise ValueError('Negative stderr commitment differs')
  for b in r['inputs']:
   if sha(Path(b['path']))!=b['sha256']:raise ValueError('Negative input changed: '+b['path'])
  negatives.append({'name':name,'stderr':text,'actual_failing_stage':'specific assertion verbatim; distinct from successful combined fixture routes','report':binding(p/'result.json')})
 out=copy.deepcopy(base);out.update({'status':'author_verification_passed_pending_independent_review','canonical_coverage':cases,'canonical_artifacts':artifacts,'discriminating_source_negatives':negatives,'full_plugin_equivalence':False,'independent_acceptance':False})
 return out

def main():
 work=Path(os.environ.get('VL_PREVOICE_REPAIR_RESULTS_ROOT',str(CAND/'work')))
 basepath=Path(os.environ.get('VL_PREVOICE_REPAIR_EXPECTED_MANIFEST',str(CAND/'prevoice-repair-verification.json')))
 base=json.loads(basepath.read_text())
 if len(sys.argv)>1 and sys.argv[1]=='--probe-rejections':
  # Own isolated symlink views never change canonical evidence/source bytes.
  output=work/'summary-negatives';output.mkdir(exist_ok=True);rows=[]
  for name,mode,prefix in [('missing','native','cache'),('failed','native','handoff'),('diagnostic','sanitized','cache'),('count','O0','rejections'),('identity','native','cache')]:
   p=output/name;p.mkdir(exist_ok=True)
   for m in ['native','sanitized','O0']:
    dest=p/('canonical-'+m);dest.mkdir(exist_ok=True)
    for f in (work/('canonical-'+m)).iterdir():
     q=dest/f.name
     if not q.exists():q.symlink_to(f.resolve(),target_is_directory=f.is_dir())
   (p/'negatives').symlink_to((work/'negatives').resolve(),target_is_directory=True) if not (p/'negatives').exists() else None
   ownbase=copy.deepcopy(base)
   target=p/('canonical-'+mode)/(prefix+'-result.json')
   if name=='missing':target.unlink()
   elif name in ['failed','count']:
    r=json.loads(target.read_text());target.unlink()
    if name=='failed':r['status']='failed'
    else:r['atomic_rejections']=0
    target.write_text(json.dumps(r)+'\n')
   elif name=='diagnostic':
    q=p/'canonical-sanitized/cache-stderr.log';q.unlink();q.write_text('runtime error: critic-injected diagnostic\n')
   elif name=='identity':ownbase['bound_source_inputs'][0]['sha256']='0'*64
   bp=p/'expected.json';bp.write_text(json.dumps(ownbase)+'\n')
   env=dict(os.environ,VL_PREVOICE_REPAIR_RESULTS_ROOT=str(p),VL_PREVOICE_REPAIR_EXPECTED_MANIFEST=str(bp),VL_PREVOICE_REPAIR_OUTPUT=str(p/'forbidden-success.json'))
   r=subprocess.run([sys.executable,str(Path(__file__).resolve())],env=env,capture_output=True,text=True)
   (p/'stdout').write_text(r.stdout);(p/'stderr').write_text(r.stderr)
   if r.returncode!=1 or (p/'forbidden-success.json').exists():raise ValueError('Summary failed open: '+name)
   rows.append({'case':name,'exit':r.returncode,'stderr':r.stderr,'success_manifest_written':False})
  (output/'result.json').write_text(json.dumps({'status':'passed_five_fail_closed_summary_probes','probes':rows},indent=2)+'\n');print(json.dumps({'status':'passed_five_fail_closed_summary_probes','cases':5}));return
 out=collect(work,base)
 probes=json.loads((work/'summary-negatives/result.json').read_text())
 if probes.get('status')!='passed_five_fail_closed_summary_probes':raise ValueError('Missing summary guards')
 out['fail_closed_summary_proof']=binding(work/'summary-negatives/result.json')
 output=Path(os.environ.get('VL_PREVOICE_REPAIR_OUTPUT',str(CAND/'prevoice-repair-verification.json')))
 output.write_text(json.dumps(out,indent=2)+'\n');print(json.dumps({'status':out['status'],'path':str(output),'sha256':sha(output)}))
if __name__=='__main__':
 try:main()
 except Exception as e:print(str(e),file=sys.stderr);sys.exit(1)
