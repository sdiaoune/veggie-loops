import json,sys
from pathlib import Path
p=Path(sys.argv[1]);results={}
for mode in ('normal','sanitized','O0'):
 w=p/mode;r=json.loads((w/'protocol.json').read_text());life=json.loads((w/'lifetime.json').read_text());assert r['status']=='matched_balance_public_name_and_event_protocol' and r['name_pairs']==120 and r['event_pairs']==36 and r['different_name_buffers']==0 and r['maximum_polyphony_state_comparisons']==40 and r['intact_engine_bridge_name_calls']==60 and r['intact_engine_bridge_event_calls']==18 and not r['full_plugin_equivalence'];assert life['instances']==96 and life['tracked_plugin_deallocations']==96 and life['tracked_numerical_deallocations']==96 and life['optional_editor_off_main_refusals']==0 and not life['original_extra_destructor_invoked'];assert not(w/'protocol.stderr').read_bytes() and not(w/'lifetime.stderr').read_bytes();results[mode]={'protocol':r,'lifetime':life}
 if mode!='O0':
  e=json.loads((w/'lifetime-editor.json').read_text());assert e['optional_editor_off_main_refusals']==96 and e['instances']==96;assert not(w/'lifetime-editor.stderr').read_bytes();results[mode]['optional_editor_lifetime']=e
  for name in ('engine-loader','engine-abi'):
   assert not(w/(name+'.stderr')).read_bytes();log=json.loads((w/(name+'.log')).read_text());assert log['status']=='passed' and not log['full_plugin_equivalence'];assert log['parameter_calls']==2400 if name=='engine-loader' else log['cases']==1200;results[mode][name]=log
assert results['normal']==results['sanitized']
assert results['O0']['protocol']==results['normal']['protocol'] and results['O0']['lifetime']==results['normal']['lifetime']
(p/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(json.dumps({'status':'matched_finite_protocol_lifetime_and_regressions','modes':list(results),'name_pairs_per_mode':120,'event_pairs_per_mode':36,'lifetime_instances_per_mode':96,'full_plugin_equivalence':False}))
