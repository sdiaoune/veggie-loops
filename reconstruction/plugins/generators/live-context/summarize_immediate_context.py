#!/usr/bin/env python3
import hashlib,json,re,sys
from pathlib import Path
p=Path(__file__).resolve().parent
if len(sys.argv)>3:raise SystemExit('Usage: summarize_immediate_context.py [project_root [work_base]]')
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else p.parents[3]
source=root/'reconstruction/plugins/generators'
candidate=source/'live-context'
work=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else root/'.tools/plugin-work/generators/live-context-public'
sha=lambda q:hashlib.sha256(q.read_bytes()).hexdigest()
def bind(q):return {'path':str(q.relative_to(root)) if q.is_relative_to(root) else str(q),'sha256':sha(q),'bytes':q.stat().st_size}
def require(v,msg):
 if not v:raise SystemExit(msg)
preExpected={'status':'passed','private_variant_prevoice_regression':True,'prevoice_delivery_fixtures':72,'intact_TExPlugin_descriptor_routes':144,'balanced_manager_retains':288,'delivered_original_context_values':360,'exact_prevoice_coefficient_words':13320,'exact_semantic_state_bytes':32904,'exact_voice_state_values':61560,'GenRender_calls':576,'exact_overwritten_audio_floats':225072,'ignored_clock_metadata_pairs':36,'filter_mode_fixtures':[10,10,10,10,8,8,8,8],'selected_native_globals_restored':True,'direct_prepared_rate_delivery':True,'native_DLL_loader_rate_production_executed':False,'active_voice_context_updates':False,'actual_application_clock_production':False,'full_plugin_equivalence':False}
liveExpected={'status':'passed_live_context_variant','fixtures':96,'exact_initial_prerenders':96,'exact_voice_state_comparisons':672,'exact_voice_state_values':63840,'exact_overwritten_audio_floats':114816,'render_calls':576,'fixtures_with_audio_difference':0,'fixtures_with_first_state_difference':0,'immediate_native_voice_word_mutations':0,'immediate_source_voice_word_mutations':0,'source_channel_replacements':0,'changed_audio_fixtures_by_action':[0]*6,'changed_first_state_fixtures_by_action':[0]*6,'changed_coefficient_words_by_action':[0,0,160,0,320,320],'new_runtime_implementation':True,'selected_wrapper_globals_restored':True,'real_application_clock_production':False,'real_scheduler_or_RT':False,'full_plugin_equivalence':False}
preparationExpected={'status':'passed_active_immediate_preparation_and_next_use','fixtures':16,'immediate_mask_differences':0,'full_fenv_restorations':240,'all_measured_masks_equal':True,'exact_prepared_words':44400,'first_native_mask':16,'first_source_mask':16,'rejected_source_contexts':304,'exact_initial_prerenders':16,'first_voice_state_comparisons':208,'immediate_native_mutations':0,'immediate_source_mutations':0,'source_channel_replacements':0,'sequential_context_operations':288,'second_voice_triggers':16,'second_voice_state_comparisons':176,'declared_only_native_coefficient_checks':128,'render_calls':192,'exact_audio_floats':20352,'selected_wrapper_globals_restored':True,'canonical_scope_extended':True,'bounded_active_immediate_preparation_FP_masks_proved':True,'full_plugin_equivalence':False}
expected={'prevoice':preExpected,'live':liveExpected,'preparation':preparationExpected}
labels=['same-tempo120','changed-tempo60','same-tempo60','PPQ-only960','PPQ-then-tempo120','rate96000','rate44100','PPQ-only240','PPQ-then-same-tempo120','group0-attack5000','group0-same-attack5000','group0-zero-curve','group0-curve16','group0-attack4000','same-active-state-restore']
maskExpected=[{'fixture':i,'label':label,'native_mask':0 if label.startswith('PPQ-only') else 16,'source_mask':0 if label.startswith('PPQ-only') else 16} for i in range(16) for label in labels]
artifactNames=['prevoice-result.json','live-result.json','preparation-result.json','prevoice-stderr.log','live-stderr.log','preparation-stderr.log','test_immediate_prevoice_regression','test_immediate_live_regression','test_immediate_preparation','VL 3 Osc/VL 3 Osc_X64.dylib','old-lazy/VL 3 Osc_X64.dylib','old-lazy-negative.stdout','old-lazy-negative.stderr','old-lazy-negative-result.json']
PINNED_COMPILED = {'immediate_channel.hpp': 'c605302a66452b790eb96731a3ade20a4236984fa1ab4edade97aa442e58806e',
 'immediate_channel.cpp': '59939a6125e4ebb4f360ae192f8775334ccad44fcb64f0551a64197fc11b39c9',
 'immediate_factory.cpp': '7914a78e0eae65c926c18f78e516d991abb32e82610411526850bf27faa2c88c',
 'immediate_coefficients.hpp': '7924811c17e99cd03b66488f7a3569f6343a85f8d1cb4864befb91340588dc28',
 'test_immediate_live_regression.mm': '4e765d7efcde3c40f492edd011964d69012b2fca1822c9fae8c42369e4ee9721',
 'test_immediate_prevoice_regression.mm': '99e5bce5529cdab93121db46a753a47fadc018bb89ce3b790c9750c53ed563e0',
 'test_immediate_preparation.mm': '67f9522b0aa9279a279a9dcd6aa4251bc688ecb17cc09b22aea84d1af83d7bdb',
 'lazy-baseline/live_context_channel.hpp': '0e72b5424575b06400417dc0fc3eefba74d324fc6e42b448c5e0ef83fe255804',
 'lazy-baseline/live_context_channel.cpp': '40a37f0c45988b4fd5f8ba21b85fb8c7cbb296978b324aeae43ff3deaeac355f',
 'lazy-baseline/live_context_factory.cpp': '367fe37707cf28cc739af8a33986bcc7f645b707643b968368864e432cced6e6'}
PUBLIC_DEPENDENCIES = {'reconstruction/plugins/generators/three_osc.hpp': 'eabb0f14671c3aeb451d3ecf18cce4d544f0e8b8e8384ab80b362848fcf319f9',
 'reconstruction/plugins/generators/three_osc_clock_context.cpp': '4ae56856c3827f05b9a5de95d1ca519a0eda627f6c5bec77926a8aa6d6baca06',
 'reconstruction/plugins/generators/three_osc_clock_context.hpp': '1be8a2b5bbee71d675b97df5dfffe1346aa0a982b67496d3447243e8dfaf0a8e',
 'reconstruction/plugins/generators/three_osc_declick.cpp': '93a5a48a9dacadacfc3fdbff5ab908ae4fb8ecb7d55dbb3daebceb39d7f2ce23',
 'reconstruction/plugins/generators/three_osc_declick.hpp': 'aa287e8c26940bcf8b0cd5dea476c25f6a54e75105e6b97bc4462f8d356ee435',
 'reconstruction/plugins/generators/three_osc_engine.cpp': '860867b36885d4c612d10bcdeaf33a7a185809789f26943bd3e4bd2ca67854ea',
 'reconstruction/plugins/generators/three_osc_envelope.hpp': '265349af010d24840b12fb20055c7932a0e53752b4179e5cce0385b1c48fc61a',
 'reconstruction/plugins/generators/three_osc_envelope_coefficients.hpp': 'fa1ec462eeab4a7918634a770033757befa6cfe9f37aeb5fab2e6fb0f64e5f57',
 'reconstruction/plugins/generators/three_osc_filter.hpp': '16a34e38104319a14e1de0c6f338ab6fb9381817640054913e73513e1b6c53a5',
 'reconstruction/plugins/generators/three_osc_filter_routing.hpp': '02a88d145fae30bb0eb9e536e3a2230fdeb5311cd91893af555c4076d69c8cd7',
 'reconstruction/plugins/generators/three_osc_gain_mix.hpp': 'bc2d71c000e0f412148ae80fc46cce52d6ebf1c214d0924906a5d8e0d8bee4e2',
 'reconstruction/plugins/generators/three_osc_legacy_tables.cpp': 'df33049821ef64472d904493c274ae077ba70f308a881212e6d701c8a86f0135',
 'reconstruction/plugins/generators/three_osc_legacy_tables.hpp': '838ee2842afe2f4f1b5ea14be0b866ede0de84e2d17a0715aae655da3ee3d119',
 'reconstruction/plugins/generators/three_osc_modulation.hpp': '6f5877b93330326f106d5c76548644ba81ccce9504596062d169b8794288fa58',
 'reconstruction/plugins/generators/three_osc_multimode_channel.h': '38a807f38c9c482b9e2b0903864d9d2defef13ce66c0424e8b0c4ce9da9e8272',
 'reconstruction/plugins/generators/three_osc_native_factory.h': 'b5dfc694cda975ee2e2a0348f6f16cce5ee94e1a721510b923c03ef5d8d20bfb',
 'reconstruction/plugins/generators/three_osc_sync_lfo.cpp': '5966c658eef2928a07e32f4ffa7913e156e89cea9e28854395e9dd77de4ba892',
 'reconstruction/plugins/generators/three_osc_sync_lfo.h': '52757f5b5012a78d697e6e29a03641d6fc0ded032bb551592657a557183ae006',
 'reconstruction/plugins/generators/three_osc_tables.hpp': 'a1afa520a7e5420a9d9a341ac4e023e2a4b9bb1cfb0ca39ade99ac7d01bbd2bc',
 'reconstruction/plugins/generators/three_osc_voice_lifecycle.cpp': '61d50da9dbfcba794811ff899cfa0d19dbb785ddbfeddd0b529f34f65eeefc79',
 'reconstruction/plugins/generators/three_osc_voice_lifecycle.h': '4a6e2b1ca34ce98e981dcce67f420de16588088e4fb83496cea63c8edf2db641',
 'reconstruction/plugins/generators/three_osc_voice_output.hpp': '3f17be324d6f79757303938ecdaab5ab1dd679cd48ab1eb5704d8f28e2dc8729',
 'reconstruction/plugins/generators/three_osc_wrapper_core.cpp': '495882f6d014e78d6d597610bccc49e3f8c10c44b862df6120ab638e5105af50',
 'reconstruction/plugins/generators/three_osc_wrapper_core.h': '7c811e6ae33cb59ccf56ca231d468490a42556808cddae5b0ffc25d2586a1b5e'}
NATIVE_IDENTITIES = {'/Applications/FL Studio 2024.app/Contents/Libs/FLEngine_x64.dylib': '22d445ddae0bc9f6fe6ab1d53e8b59659b9a9e2a07d441371e3c27704317bd37',
 '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/3x Osc_x64.dylib': 'c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c',
 '/Applications/FL Studio 2024.app/Contents/Resources/FL/Plugins/Fruity/Generators/3x Osc/engine.dylib': 'd7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f',
 '/Applications/FL Studio 2024.app/Contents/Resources/FL/Shared/dsp_ippv2_x64.dylib': 'f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1'}
LOCAL_REFERENCES = {'analysis/plugins/generators/live-context-immediate-candidate-source.json': {'sha256': '5fa07af596cc5f8f8e504a910fc1ea8e8c249b3aa2acb38e7bc3d78a4324b3b2',
                                                                              'bytes': 36861,
                                                                              'local_only': True,
                                                                              'required_by_public_recipe': False,
                                                                              'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-variant-candidate-source.json': {'sha256': '6be505977847298a1dafbcc4b3148574bd054d505e0776f47976745ff1e89325',
                                                                            'bytes': 16464,
                                                                            'local_only': True,
                                                                            'required_by_public_recipe': False,
                                                                            'reproduced_by_public_recipe': False},
 'analysis/plugins/review/root-live-immediate-combined-independent.json': {'sha256': 'caacc054c34b835ede0071b476a42ccf682c3da9f32c595910a4235a471e0555',
                                                                           'bytes': 19588,
                                                                           'local_only': True,
                                                                           'required_by_public_recipe': False,
                                                                           'reproduced_by_public_recipe': False},
 'analysis/plugins/review/root-live-immediate-independent.json': {'sha256': '4b6b6b214b82e46fcaf52139e89802b21f9501ab63078f41b6be14238191fa4b',
                                                                  'bytes': 23224,
                                                                  'local_only': True,
                                                                  'required_by_public_recipe': False,
                                                                  'reproduced_by_public_recipe': False},
 'analysis/plugins/review/live-immediate-mixer-independent.json': {'sha256': 'b5a30d2da019194d37bb8c5324888d7152712464cd3acdc1a6c15a30e4cda46e',
                                                                   'bytes': 24471,
                                                                   'local_only': True,
                                                                   'required_by_public_recipe': False,
                                                                   'reproduced_by_public_recipe': False},
 'analysis/plugins/review/live-immediate-effects-independent.json': {'sha256': '2851228493ca9ef2542d48fc6054e0062b489dd61d84a605d9e47da65e46fdea',
                                                                     'bytes': 57001,
                                                                     'local_only': True,
                                                                     'required_by_public_recipe': False,
                                                                     'reproduced_by_public_recipe': False},
 'analysis/plugins/review/live-context-effects-independent.json': {'sha256': '5a5b37f37afa77eefc6510338c2933457c5b24beb968e1f8a5c2c7c9a10d7bdb',
                                                                   'bytes': 40853,
                                                                   'local_only': True,
                                                                   'required_by_public_recipe': False,
                                                                   'reproduced_by_public_recipe': False},
 '.tools/plugin-work/review/live-context-effects-final/live-context-effects-immediate-fenv.mm': {'sha256': 'c328f64b101b9eda9196a8a0278aaa649c567937ebacecd25cb3fa53dc2285a4',
                                                                                                 'bytes': 23460,
                                                                                                 'local_only': True,
                                                                                                 'required_by_public_recipe': False,
                                                                                                 'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-immediate-coefficient-prepare.disasm': {'sha256': 'f8d36254e2b227adc1f78fedd449da651e70966245e8b8a67097bf3a82b55162',
                                                                                   'bytes': 11430,
                                                                                   'local_only': True,
                                                                                   'required_by_public_recipe': False,
                                                                                   'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-immediate-group-parameter.disasm': {'sha256': '948b19656cb07e281057266a7e9c3f9b33331984f1db412411fbf8a30a88ca62',
                                                                               'bytes': 4747,
                                                                               'local_only': True,
                                                                               'required_by_public_recipe': False,
                                                                               'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-immediate-restore.disasm': {'sha256': 'f4527baf437ab439524223922e945d5d185222153ae47734939968ad76b5edbd',
                                                                       'bytes': 4935,
                                                                       'local_only': True,
                                                                       'required_by_public_recipe': False,
                                                                       'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-config-reprepare.disasm': {'sha256': '3d7da1fa3d5fcc1135b16d46dd4dbcb2e840be6b79df835aca2663aec4306ccc',
                                                                      'bytes': 1349,
                                                                      'local_only': True,
                                                                      'required_by_public_recipe': False,
                                                                      'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-rate-handler.disasm': {'sha256': '516e30e26d0f73912eb762ef6c1ad5981daf258491c6f35b41bbcd5e06b8e4fe',
                                                                  'bytes': 1504,
                                                                  'local_only': True,
                                                                  'required_by_public_recipe': False,
                                                                  'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-rate-helper.disasm': {'sha256': '7ace1522eec0f95fb5f3d0d17f8e8253e598c9c43c60b7e33edbb898c08c3738',
                                                                 'bytes': 3968,
                                                                 'local_only': True,
                                                                 'required_by_public_recipe': False,
                                                                 'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-tempo-handler.disasm': {'sha256': '432d3d9367a745eea79a8e9fef6109d8321a5bdc60f474127bc33d603b70bdad',
                                                                   'bytes': 1434,
                                                                   'local_only': True,
                                                                   'required_by_public_recipe': False,
                                                                   'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-PPQ-store.disasm': {'sha256': 'b88c9ed742082bfec8cd8768ad570a8362c551fb149495fa1e441253ee1f8085',
                                                               'bytes': 700,
                                                               'local_only': True,
                                                               'required_by_public_recipe': False,
                                                               'reproduced_by_public_recipe': False},
 'analysis/plugins/generators/live-context-observations-frozen.json': {'sha256': '66cfb21eb204ab28beefa537f9cfac77a1b6392867e51fe7bb0cfbecc61b17e4',
                                                                       'bytes': 14399,
                                                                       'local_only': True,
                                                                       'required_by_public_recipe': False,
                                                                       'reproduced_by_public_recipe': False}}
EXTRA_CRITICS = [{'review': 'analysis/plugins/review/live-immediate-mixer-independent.json',
  'coverage': '10,840 native helper/FE comparisons; all-five-group800-byte guard/two-voice '
              'extension; independent rint-to-round tie negative. Separate from canonical group0 '
              'corpus.'},
 {'review': 'analysis/plugins/review/live-immediate-effects-independent.json',
  'coverage': '19,456 inherited sticky FE comparisons,3,599,360 cached words and1,328 source-only '
              'preservation rejects across16pairs. Separate from canonical240mask corpus.'}]
for mode in ['native','sanitized']:
 for name in artifactNames:
  require((work/('canonical-'+mode)/name).is_file(),f'Required {mode} artifact missing: {name}')
runs={}
for mode in ['native','sanitized']:
 w=work/('canonical-'+mode)
 for prefix,want in expected.items():
  r=json.loads((w/(prefix+'-result.json')).read_text())
  require({k:v for k,v in r.items() if k not in ['observations','mask_observations']}==want,f'{mode}/{prefix} corpus differs')
  if prefix=='live':require(len(r.get('observations',[]))==96,'Live observation count differs')
  if prefix=='preparation':require(r.get('mask_observations')==maskExpected,'Immediate mask observations differ')
  s=(w/(prefix+'-stderr.log')).read_text()
  require(not any(x in s for x in ['runtime error:','ERROR: AddressSanitizer','UndefinedBehaviorSanitizer','SUMMARY:']),f'{mode}/{prefix} sanitizer diagnostics rejected')
 negative=json.loads((w/'old-lazy-negative-result.json').read_text())
 require(negative=={'status':'passed_expected_rejection','exit':1,'stderr':'Preparation mask fixture 0 same-tempo120 native=16 source=0\nImmediate preparation FE masks differ\n','full_plugin_equivalence':False},'Old lazy negative differs')
 require((w/'old-lazy-negative.stderr').read_text()==negative['stderr'] and not (w/'old-lazy-negative.stdout').read_text(),'Old lazy failure evidence differs')
 runs[mode]={n:bind(w/n) for n in artifactNames}
for prefix in expected:
 require((work/'canonical-native'/(prefix+'-result.json')).read_bytes()==(work/'canonical-sanitized'/(prefix+'-result.json')).read_bytes(),'Normal/sanitized results differ')
o0={}
for name in ['VL 3 Osc_X64.dylib']+[prefix+suffix for prefix in expected for suffix in ['-result.json','-stderr.log']]:
 require((work/'extra-O0'/name).is_file(),'O0 source artifact missing: '+name)
 o0[name]=bind(work/'extra-O0'/name)
for prefix in expected:
 require((work/'extra-O0'/(prefix+'-result.json')).read_bytes()==(work/'canonical-native'/(prefix+'-result.json')).read_bytes(),'O0 corpus differs')
 s=(work/'extra-O0'/(prefix+'-stderr.log')).read_text()
 require(not any(x in s for x in ['runtime error:','ERROR: AddressSanitizer','UndefinedBehaviorSanitizer','SUMMARY:']),'O0 diagnostics rejected')
for name,want in PINNED_COMPILED.items():require(sha(candidate/name)==want,'Pinned current/baseline source changed: '+name)
for name,want in PUBLIC_DEPENDENCIES.items():require(sha(root/name)==want,'Pinned public source dependency changed: '+name)
for nativePath,want in NATIVE_IDENTITIES.items():require(sha(Path(nativePath))==want,'Installed target identity changed: '+nativePath)
closure=set()
def visit(q):
 q=q.resolve()
 if q in closure:return
 closure.add(q)
 for name in re.findall(r'#include\s+"([^\"]+)"',q.read_text()):
  options=[q.parent/name,candidate/name,source/name];c=next((v for v in options if v.is_file()),None)
  require(c is not None,'Missing quoted include '+name);visit(c)
for name in ['immediate_factory.cpp','immediate_channel.cpp','test_immediate_live_regression.mm','test_immediate_prevoice_regression.mm','test_immediate_preparation.mm']:visit(candidate/name)
for name in ['three_osc_sync_lfo.cpp','three_osc_voice_lifecycle.cpp','three_osc_declick.cpp','three_osc_wrapper_core.cpp','three_osc_engine.cpp','three_osc_legacy_tables.cpp','three_osc_clock_context.cpp']:visit(source/name)
for name in ['live_context_factory.cpp','live_context_channel.cpp']:visit(candidate/'lazy-baseline'/name)
expectedClosure={(candidate/name).resolve() for name in PINNED_COMPILED}|{(root/name).resolve() for name in PUBLIC_DEPENDENCIES}
require(closure==expectedClosure,'Exact quoted include/linked closure differs')
failClosed=json.loads((work/'summary-negative/results.json').read_text())
require(failClosed['status']=='passed_fail_closed_rejections' and len(failClosed['cases'])==4 and all(c['exit']!=0 and c['no_success_manifest'] for c in failClosed['cases']),'Fail-closed summary proof missing')
owned=list(PINNED_COMPILED)+['verify_immediate_context.sh','verify_immediate_O0.sh','IMMEDIATE_PREPARATION.md','summarize_immediate_context.py','summary_negative_probe.py']
manifest={'status':'independently_accepted_source_mechanically_promoted_pending_final_path_review','sources':{n:bind(candidate/n) for n in owned},'pinned_compiled_source_hashes':PINNED_COMPILED,'exact_quoted_include_and_linked_source_closure':{str(q.relative_to(root)):bind(q) for q in sorted(closure)},'exact_native_identities':{name:bind(Path(name)) for name in NATIVE_IDENTITIES},'runs':runs,'expected_summaries':expected,'exact_immediate_mask_observations':maskExpected,'O0_source_runs':o0,'fail_closed_summary_probe':bind(work/'summary-negative/results.json'),'local_evidence_references_not_read_or_reproduced':LOCAL_REFERENCES,'extra_critics_separate_from_canonical':EXTRA_CRITICS,'baseline_role':'Three byte-identical source support files compiled only for the known native16/source0 lazy negative; baseline is not a completed plugin. Other ignored old source/evidence is referenced by frozen hashes only.','private_helper_namespace':'veggie_loops::three_osc::immediate','changed_shared_helper_definitions':False,'runtime_changes':['Cache actual five prepared configurations at observed active preparation points','Copy cache at next use; inject current synchronized phase independently','Use distinct rint helper for measured FRINTX','Retain voice/filter/history/borrowed params/handles and PPQ-only prepared state'],'bounded_domain':'Sixteen fixed mode/flag pairs; listed raw group0 controls and same valid active state restore; nontrapping nearest-even, gradual underflow and serial nonthrowing deferred-deletion callbacks','unproved_domains':['Immediate lazy prevoice preparation timing','General fenv/trap/errno and other rounding/flush modes','Arbitrary active controls/state/release/seek/sync modes or cross-instance timing','Actual application clocks/rate production/host manager/table ownership/scheduler/RT','Original Pascal class/editor/metadata/VST/AU/full plugin'],'public_recipe_requires_ignored_private_evidence':False,'full_plugin_equivalence':False,'public_final_path_review':None}
# Write only after every required result, source/closure/target and diagnostic gate.
(p/'immediate-preparation-verification.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'status':manifest['status'],'verification_sha256':sha(p/'immediate-preparation-verification.json'),'closure_entries':len(closure)}))
