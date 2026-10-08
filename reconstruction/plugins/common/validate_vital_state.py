#!/usr/bin/env python3
"""Validate the disclosed Vital/Vial JSON+PCM16 state corpus, not all presets."""
import argparse
import base64
import json
import plistlib
import struct
from pathlib import Path


def read(path):
    raw = path.read_bytes()
    envelope = None
    if raw.startswith((b'bplist', b'<?xml')):
        envelope = plistlib.loads(raw)
        if not isinstance(envelope, dict) or not isinstance(envelope.get('jucePluginState'), bytes):
            raise ValueError('AU state lacks a jucePluginState byte payload')
        raw = envelope['jucePluginState']
    # VST3 may prepend legacy VST2 compatibility bytes and append JUCE state.
    start, end = raw.find(b'{'), raw.rfind(b'}')
    if start < 0 or end < start:
        raise ValueError('No JSON state payload')
    state = json.loads(raw[start:end + 1])
    if not isinstance(state, dict) or not isinstance(state.get('settings'), dict):
        raise ValueError('Invalid instrument state shape')
    return state, raw[:start], raw[end + 1:], envelope


def validate(before_path, after_path, tolerance=1):
    before, prefix_before, suffix_before, envelope_before = read(before_path)
    after, prefix_after, suffix_after, envelope_after = read(after_path)
    if (envelope_before is None) != (envelope_after is None):
        raise ValueError('State formats differ: both captures must use the same AU or raw envelope')
    samples = []
    for field in ('samples', 'samples_stereo'):
        first, second = before['settings']['sample'], after['settings']['sample']
        if field not in first and field not in second:
            continue
        if field not in first or field not in second:
            raise ValueError('Sample channel disappeared during restoration')
        decoded = [base64.b64decode(s[field], validate=True) for s in (first, second)]
        length = first['length']
        if not isinstance(length, int) or length < 0 or length > 1764000:
            raise ValueError('Sample length outside the disclosed domain')
        if any(len(data) != length * 2 for data in decoded):
            raise ValueError('PCM sample length does not match metadata')
        pcm = [struct.unpack('<' + str(length) + 'h', data) for data in decoded]
        delta = [abs(a - b) for a, b in zip(*pcm)]
        maximum = max(delta, default=0)
        samples.append({'channel': field, 'samples': length,
                        'changed_samples': sum(d != 0 for d in delta), 'maximum_pcm_delta': maximum})
        if maximum > tolerance:
            raise ValueError(f'{field}: PCM delta {maximum} exceeds {tolerance}')
        # All remaining JSON, including sample metadata, must match exactly.
        first.pop(field)
        second.pop(field)
    if before != after:
        raise ValueError('Persistent JSON settings changed during restoration')
    if prefix_before != prefix_after or suffix_before != suffix_after:
        raise ValueError('State envelope changed during restoration')
    if envelope_before is not None:
        envelope_before.pop('jucePluginState')
        envelope_after.pop('jucePluginState')
        if envelope_before != envelope_after:
            raise ValueError('AU persistent property envelope changed')
    return {'persistent_settings_equal': True, 'pcm_tolerance': tolerance, 'channels': samples,
            'scope': 'One captured state pair; not full plugin, preset, audio or version equivalence'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        report = validate(args.before, args.after)
    except (ValueError, KeyError, TypeError, OSError, struct.error) as error:
        report = {'passed': False, 'error': str(error), 'scope': 'Captured state pair'}
        serialized = json.dumps(report, indent=2) + '\n'
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(serialized)
        print(serialized, end='')
        raise SystemExit(1)
    report['passed'] = True
    serialized = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(serialized)
    print(serialized, end='')


if __name__ == '__main__':
    main()
