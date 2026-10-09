import sys
if sys.flags.optimize:
    raise SystemExit('Optimized verification refused before operations')
if sys.platform != 'darwin':
    raise SystemExit('This source recipe requires macOS tools')
import os
if os.environ.get('VL_TYRELL_ALLOCATION_CONTRACT_SOURCE_SLOT_GRANTED') != '1':
    raise SystemExit('An explicit own-source execution lease is required')
import argparse
p = argparse.ArgumentParser()
for name in ('driver', 'manifest'):
    p.add_argument('--expected-' + name + '-sha256', required=True)
    p.add_argument('--expected-' + name + '-bytes', type=int, required=True)
p.add_argument('--work', required=True)
args = p.parse_args()
for digest, size in ((args.expected_driver_sha256,args.expected_driver_bytes),
                     (args.expected_manifest_sha256,args.expected_manifest_bytes)):
    if len(digest) != 64 or any(ch not in '0123456789abcdef' for ch in digest) or size < 0:
        raise SystemExit('Externally pinned source identities required')
from pathlib import Path
import hashlib,json,subprocess,time,signal
PACKAGE = Path(os.path.abspath(__file__)).parent.resolve()
SELF = PACKAGE / 'verify.py'
MANIFEST = PACKAGE / 'verification.json'
DECLARED = [{'name': 'allocation_gate.hpp', 'sha256': '5de1513925d62752d5a64679bb640d1e8a9004aa4bcded740fff6fe5ea7dacd0', 'bytes': 5601}, {'name': 'allocation_provider.hpp', 'sha256': '09702182e50e76d07c6612f5bfc4b1f3dfa3fa97f8e7341527d5df37fcc6b8ce', 'bytes': 4761}, {'name': 'test_fake_ranges.cpp', 'sha256': 'edc5d3dbc08d15fd0d93897938bb23c8d018e697cc49949464d2135337afd970', 'bytes': 3759}, {'name': 'test_mock_provider.cpp', 'sha256': '1f0c8117dd17b2304e1e57946642f9a000480e5f754bacbf659afb2624a2bf99', 'bytes': 9242}, {'name': 'expectations.json', 'sha256': 'bdd271fecc2409dcf3ea70075f012822b91a1dd0b344ea230f28e0f70fc00817', 'bytes': 438}, {'name': 'README.md', 'sha256': '524c1dfcc29cf35203c03fbd0a4b7f171f68961b94dcd4a51e87a7c70d9ddb0c', 'bytes': 3861}]
inputs = [{'path':str(PACKAGE/r['name']),'sha256':r['sha256'],'bytes':r['bytes']} for r in DECLARED]
inputs += [{'path':str(SELF),'sha256':args.expected_driver_sha256,'bytes':args.expected_driver_bytes},
           {'path':str(MANIFEST),'sha256':args.expected_manifest_sha256,'bytes':args.expected_manifest_bytes}]
WORK = Path(os.path.abspath(os.path.expanduser(args.work)))
registered=[]
commands=[]
recording=[]
cleanup=[]
primary=None
created=False
profiles=[]

def need(ok, message):
    if not ok: raise RuntimeError(message)

def failure(stage, exc, **kw):
    return {'stage':stage,'type':type(exc).__name__,'message':str(exc),**kw}

def identity(path):
    digest=hashlib.sha256();size=0
    with Path(path).open('rb') as f:
        while data:=f.read(1024*1024):digest.update(data);size+=len(data)
    return {'path':str(path),'sha256':digest.hexdigest(),'bytes':size}

def audit(rows):
    result=[]
    for expected in rows:
        actual=None;error=None
        try:
            need(not Path(expected['path']).is_symlink() and Path(expected['path']).is_file(),
                 'Identity is not an ordinary package/work file')
            actual=identity(expected['path'])
            need(actual=={k:expected[k] for k in ('path','sha256','bytes')},'Missing/pending/changed identity')
        except BaseException as exc:error=failure('identity',exc,path=expected['path'])
        result.append({'expected':expected.copy(),'actual':actual,'error':error})
    return result

def register(path, category):
    need(not any(r['path']==str(path) for r in registered),'Duplicate destination')
    row={'path':str(path),'sha256':None,'bytes':None,'category':category}
    registered.append(row);return row

def save(path, data, category, slot=None):
    slot=slot if slot is not None else register(path,category)
    need(slot['sha256'] is None,'Already sealed destination')
    slot.update(sha256=hashlib.sha256(data).hexdigest(),bytes=len(data))
    try:Path(path).write_bytes(data);return True
    except BaseException as exc:recording.append(failure('write',exc,path=str(path)));return False

def encoded(value):
    return (json.dumps(value,indent=2)+'\n').encode()

def typed_equal(a,b):
    if type(a) is not type(b):return False
    if type(b) is dict:return a.keys()==b.keys() and all(typed_equal(a[k],b[k]) for k in b)
    if type(b) is list:return len(a)==len(b) and all(typed_equal(x,y) for x,y in zip(a,b))
    return a==b

def read_pinned_json(path):
    expected=next(r for r in inputs if r['path']==str(path))
    with Path(path).open('rb') as f:data=f.read(expected['bytes']+1)
    need(len(data)==expected['bytes'] and hashlib.sha256(data).hexdigest()==expected['sha256'],
         'Parsed control bytes differ from exact source commitment')
    return json.loads(data)

def seal_produced(slot):
    slot.update(identity(Path(slot['path'])))

def kill_owned(process,state):
    # No journal dependency and no blind signal to a reused process group.
    try:
        if process.poll() is not None:return
        pgid=os.getpgid(process.pid);sid=os.getsid(process.pid)
        if process.poll() is None and pgid==process.pid and sid==process.pid:
            os.killpg(process.pid,signal.SIGKILL)
            state['signals'].append('verified_owned_session_group')
    except BaseException as exc:cleanup.append(failure('group_owner_or_kill',exc))
    try:
        if process.poll() is None:
            process.kill();state['signals'].append('owned_Popen_child')
    except BaseException as exc:cleanup.append(failure('direct_child_kill',exc))

def run(name, argv):
    state={'name':name,'argv':[str(a) for a in argv],'pid':None,'exit':None,
           'waited':False,'timeout':False,'signals':[],'error':None}
    commands.append(state)
    # All output/terminal slots and attempt record precede the external call.
    out=register(WORK/(name+'.stdout'),'command_stdout')
    err=register(WORK/(name+'.stderr'),'command_stderr')
    terminal=register(WORK/(name+'.terminal.json'),'command_terminal')
    need(save(WORK/(name+'.attempt.json'),encoded(state),'command_attempt'),'Attempt publication failed')
    process=None;out_file=None;err_file=None;pending=None
    env={k:os.environ[k] for k in ('HOME','USER','LOGNAME','LANG','LC_ALL','TMPDIR') if k in os.environ}
    env.update(PATH='/usr/bin:/bin:/usr/sbin:/sbin',ASAN_OPTIONS='halt_on_error=1:abort_on_error=1',
               UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
    try:
        out_file=Path(out['path']).open('xb');err_file=Path(err['path']).open('xb')
        process=subprocess.Popen(state['argv'],stdout=out_file,stderr=err_file,env=env,
                                 cwd=WORK,start_new_session=True)
        state['pid']=process.pid;deadline=time.monotonic()+120
        while process.poll() is None:
            need(Path(out['path']).stat().st_size<=16777216 and Path(err['path']).stat().st_size<=16777216,
                 'Command capture exceeded16MiB; preserve producer bytes')
            if time.monotonic()>=deadline:state['timeout']=True;raise TimeoutError(name+' timed out')
            time.sleep(0.05)
        state['exit']=process.wait(timeout=1);state['waited']=True
    except BaseException as exc:
        pending=exc;state['error']=failure('command',exc)
    finally:
        # Every successful Popen is waited/cleaned independently of capture,
        # stat, audit, file or publication errors. Partial logs remain files.
        if process is not None:
            if not state['waited']:kill_owned(process,state)
            try:state['exit']=process.wait(timeout=30);state['waited']=True
            except BaseException as exc:
                cleanup.append(failure('wait30',exc));kill_owned(process,state)
                try:state['exit']=process.wait(timeout=10);state['waited']=True
                except BaseException as repeated:cleanup.append(failure('wait10',repeated))
        for handle in (out_file,err_file):
            if handle is not None:
                try:handle.close()
                except BaseException as exc:recording.append(failure('capture_close',exc))
        for slot in (out,err):
            try:seal_produced(slot)
            except BaseException as exc:recording.append(failure('capture_seal',exc,path=slot['path']))
        save(Path(terminal['path']),encoded(state),'command_terminal',terminal)
    if pending is not None:raise pending
    need(state['exit']==0 and state['waited'] and not cleanup and not recording,'Command failed/closure incomplete')
    with Path(out['path']).open('rb') as f:stdout=f.read(16777216+1)
    with Path(err['path']).open('rb') as f:stderr=f.read(16777216+1)
    need(len(stdout)<=16777216 and len(stderr)<=16777216,'Capture limit exceeded')
    return stdout,stderr

def inventory():
    if not created:return []
    rows=[];known={r['path']:r for r in registered}
    try:
        for path in sorted(WORK.iterdir()):
            actual=None;error=None
            try:
                need(not path.is_symlink() and path.is_file() and str(path) in known,'Unknown work artifact')
                actual=identity(path)
                need(actual=={k:known[str(path)][k] for k in ('path','sha256','bytes')},
                     'Artifact differs from sealed expected identity')
            except BaseException as exc:error=failure('inventory',exc,path=str(path))
            rows.append({'actual':actual,'error':error})
    except BaseException as exc:rows.append({'actual':None,'error':failure('enumeration',exc)})
    return rows

try:
    need(len(inputs)==8 and len({r['path'] for r in inputs})==8,'Fixed package input geometry differs')
    before=audit(inputs);need(not any(r['error'] for r in before),'Source preflight differs')
    manifest=read_pinned_json(MANIFEST);expectations=read_pinned_json(PACKAGE/'expectations.json')
    need(typed_equal(manifest['compiled_sources'],DECLARED[:4]),'Manifest C++source declaration differs')
    need(typed_equal(manifest['all_source_files'],DECLARED+[{'name':'verify.py','sha256':args.expected_driver_sha256,'bytes':args.expected_driver_bytes}]),'Manifest exact source declaration differs')
    need(manifest['full_plugin_equivalence'] is False and manifest['scope']=='caller_supplied_model_and_controlled_callbacks_only','Manifest scope differs')
    WORK=WORK.resolve()
    need(WORK!=PACKAGE and PACKAGE not in WORK.parents and WORK not in PACKAGE.parents and
         WORK.parent.is_dir() and not WORK.exists(),'Fresh separate work required')
    WORK.mkdir();created=True
    need(save(WORK/'preflight.json',encoded(before),'source_preflight'),'Preflight publication failed')
    for fixture in ('ranges','provider'):
        for mode in ('normal','fatal'):
            name=fixture+'-'+mode;exe=WORK/name;product=register(exe,'own_product')
            flags=['/usr/bin/clang++','-arch','x86_64','-std=c++20','-O2','-fno-fast-math',
                   '-ffp-contract=off','-Wall','-Wextra','-Werror']
            if mode=='fatal':flags+=['-fsanitize=address,undefined,float-cast-overflow',
                '-fno-sanitize-recover=all','-fno-omit-frame-pointer']
            source=PACKAGE/('test_fake_ranges.cpp' if fixture=='ranges' else 'test_mock_provider.cpp')
            out,err=run(name+'-compile',flags+[source,'-o',exe]);need(out==b'' and err==b'','Unexpected compiler diagnostic')
            out,err=run(name+'-sign',['/usr/bin/codesign','--force','--sign','-',exe]);need(out==b'' and (err==b'' or err==(str(exe)+': replacing existing signature\n').encode()),'Unexpected signing output')
            out,err=run(name+'-strict',['/usr/bin/codesign','--verify','--strict',exe]);need(out==b'' and err==b'','Strict verification failed')
            out,err=run(name+'-details',['/usr/bin/codesign','-dv','--verbose=4',exe]);need(out==b'' and b'Signature=adhoc' in err and b'Format=Mach-O thin (x86_64)' in err,'Signature metadata differs')
            out,err=run(name+'-architecture',['/usr/bin/lipo','-archs',exe]);need(out.strip()==b'x86_64' and err==b'','Owned architecture differs')
            seal_produced(product)
            before_use=audit(inputs);need(not any(r['error'] for r in before_use),'Source changed before product use')
            need(save(WORK/(name+'-before-use.json'),encoded(before_use),'source_before_use'),'Before-use publication failed')
            need(identity(exe)=={k:product[k] for k in ('path','sha256','bytes')},'Product changed before use')
            out,err=run(name+'-run',[exe]);need(err==b'','Runtime diagnostic')
            actual=json.loads(out);need(typed_equal(actual,expectations[fixture]),'Typed scalar oracle differs')
            profiles.append({'profile':name,'result':actual,'product':{k:product[k] for k in ('path','sha256','bytes')}})
    need(len(profiles)==4 and len(commands)==24,'Expected exactly4profiles/24commands')
except BaseException as exc:
    primary=failure('primary',exc)
finally:
    source_post=audit(inputs);output_post=audit(registered);artifacts=inventory()
    if created:
        save(WORK/'result.json',encoded({'status':'provisional_own_source_result_requires_final_audit_and_clean_caller',
            'profiles':profiles,'commands':commands,'primary_failure':primary,'source_post':source_post,
            'outputs':output_post,'artifacts':artifacts,'recording_errors':recording.copy(),'cleanup_errors':cleanup.copy(),
            'full_plugin_equivalence':False}),'result_publication')
    source_post=audit(inputs);output_post=audit(registered);artifacts=inventory()
    if created:
        save(WORK/'postflight.json',encoded({'source_post':source_post,'outputs':output_post,'artifacts':artifacts,
            'primary_failure':primary,'recording_errors':recording.copy(),'cleanup_errors':cleanup.copy(),
            'requires_clean_exit_and_final_current_identities':True}),'postflight_publication')
    source_post=audit(inputs);output_post=audit(registered);artifacts=inventory()
    eligible=(created and primary is None and len(profiles)==4 and not recording and not cleanup and
              not any(r['error'] for r in source_post+output_post+artifacts))
if not eligible:
    sys.stderr.write(json.dumps({'status':'failed_own_source_verification','primary_failure':primary,
        'source_post':source_post,'outputs':output_post,'artifacts':artifacts,'recording_errors':recording,
        'cleanup_errors':cleanup,'profiles':profiles,'commands':commands})+'\n')
    raise SystemExit(1)
print(json.dumps({'status':'passed_own_source_contract_profiles_only','profiles':4,
    'geometry_rejections_per_mode':20,'controlled_provider_cases_per_mode':25,'own_signed_x86_products':4,
    'result':identity(WORK/'result.json'),'postflight':identity(WORK/'postflight.json'),
    'live_bounds_certified':False,'actual_quiescence_established':False,
    'owner_logical_prefix_established':False,'other_table_logical_spans_established':False,
    'original_loaded_or_called':False,'full_plugin_equivalence':False}))
