#!/usr/bin/env python3
"""Bind the two default prepared-clock replays without publishing native data."""
import hashlib,json
from pathlib import Path
source=Path(__file__).resolve().parent
project=source.parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
names=['three_osc_clock_context.hpp','three_osc_clock_context.cpp','test_three_osc_clock_context.mm','verify-clock-context.sh','CLOCK_CONTEXT.md','summarize_clock_context.py']
work=project/'.tools/plugin-work/generators'
runs={}
for mode in ['native','sanitized']:
 required=work/('clock-context-'+mode)/'result.json'
 if not required.exists():raise SystemExit('Required default replay result missing: '+str(required))
for mode in ['native','sanitized']:
 folder=work/('clock-context-'+mode)
 result=folder/'result.json'
 data=json.loads(result.read_text())
 if data.get('status')!='passed':raise SystemExit('Replay did not pass: '+str(result))
 runs[mode]={'result':data,'result_sha256':sha(result),'artifacts_sha256':{name:sha(folder/name) for name in ['libVLClockContext.dylib','test_clock_context']}}
manifest={
 'schema_version':1,'status':'builder_verified_pending_independent_review',
 'source_sha256':{str((source/n).relative_to(project)):sha(source/n) for n in names},
 'dependency_sha256':{},
 'target_identity':{'platform':'macOS arm64 only','engine_universal_sha256':'22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37','engine_arm64_sha256':'04db862b730950c5e2b678e5477900bec29ab839bf35611dce92be1795636eb0'},
 'commands':['./reconstruction/plugins/generators/verify-clock-context.sh','./reconstruction/plugins/generators/verify-clock-context.sh --sanitize'],
 'builder_runs':runs,
 'measured_protocol':{'cpp_host_constructor':'0xb4cd20','cpp_host_interface_offset':16,'cpp_host_bytes':24,'host_dispatcher':'0x3d00e0','ticks_jump_target':'0x3d2074','ticks_store':'0x3d230c','time_signature_producer':'0x32e000','tempo_producer':'0x32e1f0','plugin_resolution_helper':'0x595570','cpp_plugin_constructor':'0xb4c7c0','node_vmt':'0x1076760','node_bytes':320,'signature_field':288,'selected_global_snapshot_spans':12,'snapshot_span_bytes':8},
 'scope':{
  'arithmetic':'Prepared cached/active/future GT_Ticks, nearest-even low32 local subtraction and post-conversion sample offset; only t1 is written',
  'successful_domain':'Finite cached/fractional/input-offset magnitudes<=2^52, samples/tick[1,2^32], nonnegative int32 latency, valid int32 scalar fields and live borrowed C++ objects',
  'fp':'Strict separate operations, nearest-even, gradual underflow; focused finite rint/FRINTX exception masks compared, no general fenv/trap parity',
  'corpus':'12000 ordinary tick cases plus64 cached signedzero/ties/int32,uint32 and2^52 conversion edges;6000 direct descriptor contexts with twelve clock values including low32 overflow to0',
  'descriptor':'Prepared signature1..1024/PPQ4..2^20/tempo(0,1000]/clock[1,2^32]. Intact engine direct producer+resolution executes; manager refcount/getter replaced; final calls cross actual CPP plugin adapter',
  'rate':'Prepared rate8000..384000 copy; actual loader dispatcher4 producer statically mapped, not replayed here',
  'state':'Full controlled320-byte sender compared, only12-byte signature changes; twelve selected8-byte native spans restored and readback verified; no claim over all native globals',
  'ownership':'Caller-owned controlled host/sender/interface/packet; nonthrow callbacks on valid corpus; serial standalone process. No application-owned objects are present',
  'rejections':'34 new-source scalar checks only; invalid native calls excluded',
  'sanitizers':'New separately compiled library and harness instrumented; installed engine uninstrumented',
  'missing':['Actual live engine clock production/recomputation','Queued and real application context/project/voice delivery','Original manager/interface and application host/sender ownership','Scheduler, atomic lists, threads and real-time behavior','Whole generator/plugin/factory equivalence']},
 'author_rounding_repair':{'prior_candidate_sha256':'60e65c616d3fbac70323ef39328553b013cdca7a273b16f2cc134fd7d2c996cf','prior_cpp_sha256':'36f2d243fd05856d772d31f701080ddf4590e100b057e074fc7489d264e693c9','independent_finding_sha256':'119cb153670781d909c9ceb0ffd5861f5b8bc1c8d297251d26ac099252a36932','runtime_change':'roundedWord nearbyint to rint only','old_nearbyint_negative_control':'Final focused fixture fails with Focused tick rounding bits/exception mask differs','old_evidence_preserved':True},
 'focused_rounding_status':{'rounding_helper':'rint, matching measured FRINTX','cleared_masks':'FE_ALL_EXCEPT:0 orFE_INEXACT','cached_cases':40,'descriptor_cases':14,'full_fenv_snapshots_restored':2,'general_fenv_or_enabled_trap_equivalence':False},
 'independent_review_pending':True,'prepared_clock_component_rebuilt':True,'actual_application_clock_production':False,'actual_application_context_delivery_rebuilt':False,'actual_application_host_rebuilt':False,'actual_host_scheduling_rebuilt':False,'full_plugin_recompiled':False,'full_plugin_equivalence':False}
(source/'clock-context-verification.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'status':manifest['status'],'bound_default_runs':list(runs),'source_files':len(names)}))
