#!/usr/bin/env python3
import json,pathlib,shutil,subprocess,sys
candidate=pathlib.Path(__file__).resolve().parent
root=pathlib.Path(sys.argv[1]).resolve() if len(sys.argv)>1 else candidate.parents[3]
if len(sys.argv)>2:raise SystemExit('Usage: summary_negative_probe.py [project_root]')
canonical=root/'.tools/plugin-work/generators/live-context-public'
work=canonical/'summary-negative';work.mkdir(parents=True,exist_ok=True)
results=[]
for name,keep in [('none',[]),('native_only',['native']),('sanitized_only',['sanitized']),('failed_preparation',['native','sanitized'])]:
 case=work/name;case.mkdir(exist_ok=True)
 shutil.copyfile(candidate/'summarize_immediate_context.py',case/'summarize_immediate_context.py')
 for mode in keep:
  source=canonical/('canonical-'+mode);target=case/source.name
  shutil.copytree(source,target,dirs_exist_ok=True)
 if name=='failed_preparation':
  f=case/'canonical-sanitized/preparation-result.json';r=json.loads(f.read_text());r['status']='failed';f.write_text(json.dumps(r)+'\n')
 manifest=case/'immediate-preparation-verification.json'
 if manifest.exists():raise SystemExit('Unexpected stale failure manifest')
 r=subprocess.run([sys.executable,str(case/'summarize_immediate_context.py'),str(root),str(case)],capture_output=True,text=True)
 assert r.returncode!=0 and not manifest.exists(),name
 if name=='none':assert 'Required native artifact missing:' in r.stderr
 elif name=='native_only':assert 'Required sanitized artifact missing:' in r.stderr
 elif name=='sanitized_only':assert 'Required native artifact missing:' in r.stderr
 else:assert 'sanitized/preparation corpus differs' in r.stderr
 results.append({'case':name,'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'no_success_manifest':not manifest.exists()})
(work/'results.json').write_text(json.dumps({'status':'passed_fail_closed_rejections','cases':results},indent=2)+'\n')
print(json.dumps({'status':'passed_fail_closed_rejections','cases':len(results)}))
