#!/usr/bin/env python3
"""Read-only local Mach-O inventory; no target bytes are written to the report."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

MAGICS = {b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf', b'\xce\xfa\xed\xfe', b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xfe\xed\xfa\xcf'}
CPUS = {7: 'i386', 0x01000007: 'x86_64', 12: 'arm', 0x0100000c: 'arm64'}


def thin(data, offset, size):
    magic = data[offset:offset + 4]
    if magic not in MAGICS or magic[:2] == b'\xca\xfe':
        raise ValueError('Invalid thin Mach-O magic')
    endian = '<' if magic[0] in (0xce, 0xcf) else '>'
    is64 = magic in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf')
    header = 32 if is64 else 28
    if size < header or offset + size > len(data):
        raise ValueError('Truncated Mach-O slice')
    cpu, subtype = struct.unpack_from(endian + 'II', data, offset + 4)
    ncmds, cmdbytes = struct.unpack_from(endian + 'II', data, offset + 16)
    cursor = offset + header
    command_end = cursor + cmdbytes
    if command_end > offset + size or ncmds > cmdbytes // 8:
        raise ValueError('Invalid load-command bounds')
    function_count = None
    for _ in range(ncmds):
        if cursor + 8 > command_end:
            raise ValueError('Truncated load command')
        command, length = struct.unpack_from(endian + 'II', data, cursor)
        if length < 8 or cursor + length > command_end:
            raise ValueError('Invalid load command size')
        if command == 0x26:
            if length < 16:
                raise ValueError('Truncated function-start command')
            start, count = struct.unpack_from(endian + 'II', data, cursor + 8)
            if start + count > size:
                raise ValueError('Invalid function-start bounds')
            encoded = data[offset + start:offset + start + count]
            function_count, delta, shift = 0, 0, 0
            for byte in encoded:
                delta |= (byte & 0x7f) << shift
                if byte & 0x80:
                    shift += 7
                    if shift > 63:
                        raise ValueError('Oversized function-start delta')
                else:
                    if delta == 0:
                        break
                    function_count += 1
                    delta, shift = 0, 0
        cursor += length
    return {'architecture': CPUS.get(cpu, hex(cpu)), 'cpu_subtype': subtype,
            'bytes': size, 'function_starts': function_count}


def slices(data):
    if data[:4] not in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        return [thin(data, 0, len(data))]
    if len(data) < 8:
        raise ValueError('Truncated fat header')
    count = struct.unpack_from('>I', data, 4)[0]
    wide = data[:4] == b'\xca\xfe\xba\xbf'
    stride = 32 if wide else 20
    if count > (len(data) - 8) // stride:
        raise ValueError('Invalid fat architecture bounds')
    result = []
    for index in range(count):
        cursor = 8 + index * stride
        offset, size = struct.unpack_from('>QQ' if wide else '>II', data, cursor + 8)
        result.append(thin(data, offset, size))
    return result


def category(path, root):
    relative = path.relative_to(root).as_posix()
    for name in ('Effects', 'Generators'):
        if '/Plugins/Fruity/' + name + '/' in '/' + relative:
            return 'bundled_' + name.lower()
    if '/Shared/' in '/' + relative:
        return 'bundled_dependency'
    if root.name == 'Plug-Ins':
        return 'external_plugin_or_dependency'
    return 'fl_core_or_tool'


def inventory(roots):
    records, errors, seen = [], [], set()
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob('*')):
            if not path.is_file() or path.is_symlink():
                continue
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            try:
                with path.open('rb') as source:
                    if source.read(4) not in MAGICS:
                        continue
                data = path.read_bytes()
                records.append({'path': str(path), 'category': category(path, root),
                                'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                                'slices': slices(data), 'full_recompiled': False})
            except (OSError, ValueError, struct.error) as error:
                errors.append({'path': str(path), 'error': str(error)})
    return {'roots': [str(root) for root in roots], 'binary_count': len(records),
            'unique_binary_digests': len({r['sha256'] for r in records}),
            'binary_bytes': sum(r['bytes'] for r in records),
            'errors': errors, 'binaries': records, 'all_components_recompiled': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', action='append', type=Path)
    parser.add_argument('--output', type=Path, default=Path('analysis/plugins/inventory/macho-corpus.json'))
    args = parser.parse_args()
    roots = args.root or [Path('/Applications/FL Studio 2024.app/Contents'),
                          Path('/Library/Audio/Plug-Ins'), Path.home() / 'Library/Audio/Plug-Ins']
    report = inventory(roots)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    summary = {key: value for key, value in report.items() if key not in ('binaries', 'roots')}
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
