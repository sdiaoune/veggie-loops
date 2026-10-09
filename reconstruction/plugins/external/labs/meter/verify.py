#!/usr/bin/env python3
"""Standalone verification of the caller-managed meter's own source contract."""
import sys
if sys.flags.optimize:
    raise SystemExit('Optimized Python is unsupported; no work/tool action has occurred')
import argparse
import os
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check-only', action='store_true', help='validate only the package source closure')
parser.add_argument('--work', help='fresh output directory; required for a compiler replay')
parser.add_argument('--manifest-sha256', help='optional externally pinned verification.json digest')
args = parser.parse_args()
if not args.check_only and os.environ.get('VL_LABS_METER_SOURCE_SLOT_GRANTED') != '1':
    raise SystemExit('An explicit sole source/compiler lease is required')
if not args.check_only and not args.work:
    raise SystemExit('A fresh --work directory is required')
import hashlib
import json
from pathlib import Path
import platform
import subprocess
if not args.check_only and (sys.platform != 'darwin' or platform.machine() not in ('arm64', 'aarch64')):
    raise SystemExit('This recipe requires macOS arm64')
OWN = Path(__file__).resolve().parent
MAP = OWN / 'verification.json'
PUBLIC_NAMES = ('meter.cpp', 'meter.hpp', 'test_meter_contract.cpp', 'contract_boundaries.hpp',
                'expected-results.json', 'semantic-mutants.json', 'verify.py', 'README.md')
COMPILE_NAMES = ('meter.cpp', 'meter.hpp', 'test_meter_contract.cpp', 'contract_boundaries.hpp')


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def identity(path):
    digest = hashlib.sha256()
    size = 0
    with path.open('rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(data)
            size += len(data)
    return {'sha256': digest.hexdigest(), 'bytes': size}


def locate(name):
    path = Path(name)
    return path if path.is_absolute() else OWN / path


def audit_rows(rows):
    attempted = []
    for wanted in rows:
        row = {'path': wanted['path'], 'category': wanted.get('category'),
               'origin': wanted.get('origin'),
               'expected': {key: wanted.get(key) for key in ('sha256', 'bytes')},
               'actual': None, 'matched': False, 'error': None}
        try:
            path = locate(row['path'])
            require(not path.is_symlink(), 'Symbolic-link input/output is unsupported')
            row['actual'] = identity(path)
            row['matched'] = row['actual'] == row['expected']
            if not row['matched']:
                row['error'] = 'identity differs or output was not sealed'
        except BaseException as error:
            row['error'] = type(error).__name__ + ': ' + str(error)
        attempted.append(row)
    return attempted


def exact(a, b):
    require(type(a) is type(b), 'Result scalar/container type differs')
    if type(b) is dict:
        require(set(a) == set(b), 'Result keys differ')
        for key in b:
            exact(a[key], b[key])
    elif type(b) is list:
        require(len(a) == len(b), 'Result array length differs')
        for x, y in zip(a, b):
            exact(x, y)
    else:
        require(a == b, 'Result scalar differs')


def record(path):
    return {'path': str(path), **identity(path)}


# Output identities are registered before each attempted write/child command.
# Compiler products begin as pending and are sealed after signing, before use.
generated = []


def pending(path, category):
    require(all(row['path'] != str(path) for row in generated), 'Duplicate generated output')
    row = {'category': category, 'path': str(path), 'sha256': None, 'bytes': None}
    generated.append(row)
    return row


def seal(row, data):
    require(row['sha256'] is None, 'Generated output identity already sealed')
    row.update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))


def write_bytes(path, data, registered=None):
    row = registered if registered is not None else pending(path, 'generated_record')
    seal(row, data)
    path.write_bytes(data)


def write(path, value):
    write_bytes(path, (json.dumps(value, indent=2) + '\n').encode())


def run(argv, stem, environment, expected_exit=0):
    stdout = stem.with_suffix('.stdout')
    stderr = stem.with_suffix('.stderr')
    command = stem.with_suffix('.command.json')
    slots = [pending(stdout, 'command_stdout'), pending(stderr, 'command_stderr'),
             pending(command, 'command_record')]
    result = subprocess.run([str(arg) for arg in argv], capture_output=True, text=True, env=environment)
    write_bytes(stdout, result.stdout.encode(), slots[0])
    write_bytes(stderr, result.stderr.encode(), slots[1])
    write_bytes(command, (json.dumps({'argv': [str(arg) for arg in argv],
                                   'exit': result.returncode}, indent=2) + '\n').encode(), slots[2])
    require(result.returncode == expected_exit, 'Command failed: ' + str(stem))
    return result


def compile_sign(directory, meter, mode, environment):
    expected_meter = next(row for row in copies if row['path'] == str(meter))
    protected_inputs = [row for row in copies if row['category'] == 'execution_copy'] + [expected_meter]
    require(all(row['matched'] for row in audit_rows(protected_inputs)),
            'Frozen copy/mutation input changed before compiler')
    directory.mkdir(parents=True, exist_ok=False)
    flags = ['clang++', '-arch', 'arm64', '-std=c++20', '-O0' if mode == 'O0' else '-O2',
             '-ffp-contract=off', '-fno-fast-math', '-Wall', '-Wextra', '-Werror', '-I', str(project)]
    if mode == 'fatal':
        flags += ['-fsanitize=address,undefined,float-cast-overflow',
                  '-fno-sanitize-recover=all', '-fno-omit-frame-pointer']
    exe = directory / 'test'
    product_slot = pending(exe, 'compiled_product')
    result = run([*flags, project / 'test_meter_contract.cpp', meter, '-o', exe],
                 directory / 'compile', environment)
    require(result.stdout == '' and result.stderr == '', 'Compiler diagnostic')
    signed = run(['codesign', '--force', '--sign', '-', exe], directory / 'sign', environment)
    require(signed.stdout == '' and signed.stderr in ('', str(exe) + ': replacing existing signature\n'),
            'Signing diagnostic')
    verified = run(['codesign', '--verify', '--strict', exe], directory / 'strict', environment)
    require(verified.stdout == '' and verified.stderr == '', 'Strict signature diagnostic')
    details = run(['codesign', '-dv', '--verbose=4', exe], directory / 'signature-details', environment)
    require(details.stdout == '' and 'Signature=adhoc' in details.stderr, 'Ad-hoc signature absent')
    arch = run(['lipo', '-archs', exe], directory / 'architecture', environment)
    require(arch.stdout.strip() == 'arm64' and arch.stderr == '', 'Architecture differs')
    product_slot.update(identity(exe))
    # Strict signing and architecture precede every use. Inputs are rechecked
    # before use; every source/manifest is also attempted in outer finally.
    checked = audit_rows(protected_inputs + [product_slot])
    require(all(row['matched'] for row in checked), 'Execution input/product changed')
    return exe


primary_failure = None
recording_failures = []
positives = []
negatives = []
signed_products = []
created = False
result = None
copies = []
# Even malformed/missing metadata retains all nine attempted source identities.
public_rows = [{'category': 'public_source', 'path': str(OWN / name),
                'sha256': None, 'bytes': None} for name in PUBLIC_NAMES]
map_row = {'category': 'public_manifest', 'path': str(MAP), 'sha256': None, 'bytes': None}
work = None
postflight = []
try:
    require(not MAP.is_symlink(), 'Symbolic-link manifest is unsupported')
    map_row.update(identity(MAP))
    if args.manifest_sha256 is not None:
        require(map_row['sha256'] == args.manifest_sha256, 'External manifest digest differs')
    manifest = json.loads(MAP.read_text())
    require(manifest['schema'] == 'vl_labs_meter_standalone_source_contract_v1', 'Manifest schema differs')
    exact(manifest['scope'], {'original_called': False, 'native_equivalence': False,
                              'full_plugin_equivalence': False, 'audio_reconstruction': False,
                              'format_reconstruction': False})
    exact(manifest['planned_counts'], {'positive_profiles': 3, 'fatal_semantic_negatives': 9,
                                       'signed_strict_arm64_products': 12})
    rows = manifest['files']
    require(type(rows) is list and len(rows) == len(PUBLIC_NAMES), 'Source closure count differs')
    require(all(type(row) is dict and set(row) == {'path', 'sha256', 'bytes'} for row in rows),
            'Unexpected source identity schema')
    require({row['path'] for row in rows} == set(PUBLIC_NAMES) and
            len({row['path'] for row in rows}) == len(rows), 'Source paths differ or duplicate')
    for row in rows:
        require(type(row['sha256']) is str and len(row['sha256']) == 64 and
                all(char in '0123456789abcdef' for char in row['sha256']) and
                type(row['bytes']) is int and row['bytes'] >= 0, 'Malformed source identity')
    public_rows = [{'category': 'public_source', 'path': str(OWN / row['path']),
                    'sha256': row['sha256'], 'bytes': row['bytes']} for row in rows]
    preflight = audit_rows(public_rows + [map_row])
    require(all(row['matched'] for row in preflight), 'Public source/manifest preflight failed')
    expected = json.loads((OWN / 'expected-results.json').read_text())
    exact(expected, {'status': 'passed_own_meter_source_contract_v2', 'lookup_boundary_cases': 16,
                     'transfer_boundary_cases': 4, 'state_boundary_cases': 9,
                     'atomic_rejections': 128, 'original_called': False,
                     'native_equivalence': False, 'full_plugin_equivalence': False})
    mutations = json.loads((OWN / 'semantic-mutants.json').read_text())['mutants']
    require(type(mutations) is list and len(mutations) == 9 and
            len({mutation['id'] for mutation in mutations}) == 9, 'Mutation count/identity differs')
    for mutation in mutations:
        require(type(mutation['id']) is str and mutation['id'] and
                all(char.isascii() and (char.isalnum() or char == '_') for char in mutation['id']),
                'Unsafe mutation output path')
        exact({key: mutation[key] for key in ('expected_exit', 'expected_stdout', 'fatal_sanitizers',
                                            'original_called', 'native_equivalence', 'full_plugin_equivalence')},
              {'expected_exit': 1, 'expected_stdout': '', 'fatal_sanitizers': True,
               'original_called': False, 'native_equivalence': False, 'full_plugin_equivalence': False})
    if not args.check_only:
        work = Path(args.work).expanduser().resolve()
        require(work != OWN and not work.is_relative_to(OWN) and not OWN.is_relative_to(work),
                'Work directory must be separate from the source package')
        require(work.parent.is_dir() and not work.exists(), 'Fresh work with an existing parent is required')
        project = work / 'sources'
        by_name = {row['path']: row for row in rows}
        for name in COMPILE_NAMES:
            row = by_name[name]
            copies.append({'category': 'execution_copy', 'path': str(project / name),
                           'origin': name, 'sha256': row['sha256'], 'bytes': row['bytes']})
        for mutation in mutations:
            copies.append({'category': 'generated_mutant',
                           'path': str(work / 'mutants' / mutation['id'] / 'meter.cpp'),
                           'sha256': mutation['generated_meter_sha256'],
                           'bytes': mutation['generated_meter_bytes']})
        seed = {'records': copies.copy(), 'original_called': False, 'native_equivalence': False}
        seed_bytes = (json.dumps(seed, indent=2) + '\n').encode()
        copies.append({'category': 'generated_execution_map', 'path': str(work / 'execution-inputs.json'),
                       'sha256': hashlib.sha256(seed_bytes).hexdigest(), 'bytes': len(seed_bytes)})
        registry_bytes = (json.dumps({'registered_before_attempted_writes': copies.copy()}, indent=2) + '\n').encode()
        copies.append({'category': 'generated_registry', 'path': str(work / 'registered-inputs.json'),
                       'sha256': hashlib.sha256(registry_bytes).hexdigest(), 'bytes': len(registry_bytes)})
        # All four copies, nine mutation sources, map and registry are registered
        # before work/child mkdir, copy or individual generated writes.
        work.mkdir(exist_ok=False)
        created = True
        (work / 'registered-inputs.json').write_bytes(registry_bytes)
        write(work / 'preflight.json', preflight)
        project.mkdir()
        for row in copies:
            if row['category'] == 'execution_copy':
                Path(row['path']).write_bytes(locate(row['origin']).read_bytes())
        (work / 'execution-inputs.json').write_bytes(seed_bytes)
        copied = audit_rows([row for row in copies if row['category'] != 'generated_mutant'])
        write(work / 'copy-postflight.json', copied)
        require(all(row['matched'] for row in copied), 'Registered copies/map/registry changed')
        (work / 'tmp').mkdir()
        (work / 'compiler-cache').mkdir()
        environment = dict(os.environ, TMPDIR=str(work / 'tmp'),
                           CLANG_MODULE_CACHE_PATH=str(work / 'compiler-cache'),
                           ASAN_OPTIONS='halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1')
        for mode in ('normal', 'fatal', 'O0'):
            directory = work / mode
            exe = compile_sign(directory, project / 'meter.cpp', mode, environment)
            signed_products.append(record(exe))
            output = run([exe], directory / 'runtime', environment)
            require(output.stderr == '', 'Positive source runtime diagnostic')
            payload = json.loads(output.stdout)
            exact(payload, expected)
            positives.append({'mode': mode, 'result': payload, 'artifact': record(exe)})
            write(directory / 'result.json', positives[-1])
        source = (project / 'meter.cpp').read_text()
        for mutation in mutations:
            directory = work / 'mutants' / mutation['id']
            directory.mkdir(parents=True, exist_ok=False)
            require(source.count(mutation['before']) == 1, 'Mutation anchor not unique')
            changed = source.replace(mutation['before'], mutation['after'], 1)
            meter = directory / 'meter.cpp'
            meter.write_text(changed)
            require(identity(meter) == {'sha256': mutation['generated_meter_sha256'],
                                        'bytes': mutation['generated_meter_bytes']},
                    'Generated mutation differs')
            build = directory / 'build'
            exe = compile_sign(build, meter, 'fatal', environment)
            signed_products.append(record(exe))
            output = run([exe], build / 'runtime', environment, expected_exit=1)
            require(output.stdout == mutation['expected_stdout'] and
                    output.stderr == mutation['expected_stderr'], 'Semantic negative diagnostic differs')
            require(not any(token in output.stderr for token in ('Sanitizer', 'runtime error:', 'UndefinedBehavior')),
                    'Negative failed by instrumentation instead of semantic assertion')
            negatives.append({'id': mutation['id'], 'exit': 1, 'diagnostic': output.stderr,
                              'source': record(meter), 'artifact': record(exe)})
            write(build / 'result.json', negatives[-1])
        require(len(positives) == 3 and len(negatives) == 9 and len(signed_products) == 12,
                'Contract profile/negative/product counts differ')
except BaseException as error:
    primary_failure = {'type': type(error).__name__, 'message': str(error)}
finally:
    # This happens even after setup, partial-copy, command or recording failure.
    postflight = audit_rows(public_rows + [map_row] + copies + generated)
    audit_failed = any(not row['matched'] for row in postflight)
    if not args.check_only and primary_failure is None and not audit_failed:
        result = {'status': 'passed_bounded_own_LABS_meter_source_contract_v2',
                  'eligibility_requires_clean_outer_exit_and_all_final_audits': True,
                  'positive_profiles': positives, 'fatal_semantic_negatives': negatives,
                  'signed_strict_arm64_products': signed_products, 'original_called': False,
                  'native_equivalence': False, 'full_plugin_equivalence': False}
        try:
            write(work / 'result.json', result)
        except BaseException as error:
            recording_failures.append({'category': 'result_publication_failure',
                                       'type': type(error).__name__, 'message': str(error)})
    # Reaudit after result publication, then protect the final report itself.
    after_result = audit_rows(public_rows + [map_row] + copies + generated)
    if created:
        try:
            write(work / 'final-postflight.json', {'primary_failure': primary_failure,
                                                  'recording_failures': recording_failures,
                                                  'audit_rows_after_result': after_result,
                                                  'registered_inputs': copies,
                                                  'completed_positives': positives,
                                                  'completed_negatives': negatives,
                                                  'original_called': False,
                                                  'isolated_result_file_is_not_a_pass': True})
        except BaseException as error:
            recording_failures.append({'category': 'postflight_recording_failure',
                                       'type': type(error).__name__, 'message': str(error)})
    # Includes the report just attempted, every pending/sealed command/product,
    # all expected copies/mutants/maps and all nine public identities.
    postflight = audit_rows(public_rows + [map_row] + copies + generated)
    audit_failed = any(not row['matched'] for row in postflight)
if primary_failure is not None or audit_failed or recording_failures:
    raise RuntimeError(json.dumps({'primary_failure': primary_failure,
                                  'audit_failed': audit_failed,
                                  'recording_failures': recording_failures,
                                  'all_registered_inputs_attempted': len(postflight),
                                  'final_audit_rows': postflight,
                                  'outputs_preserved': None if work is None else str(work)}))
if args.check_only:
    print(json.dumps({'status': 'passed_source_closure_check_only', 'public_identities': len(postflight),
                      'manifest': record(MAP), 'compiler_called': False, 'original_called': False}))
else:
    print(json.dumps({'status': result['status'], 'profiles': 3, 'fatal_negatives': 9,
                      'signed_strict_arm64_products': 12, 'original_called': False,
                      'native_equivalence': False, 'full_plugin_equivalence': False,
                      'all_final_audits_passed': True, 'final_identities': len(postflight),
                      'final_postflight': record(work / 'final-postflight.json')}))
