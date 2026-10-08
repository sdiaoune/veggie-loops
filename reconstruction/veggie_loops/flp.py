"""Lossless framing reader for the observed FLP chunk/event format.

This independently written module decodes framing only. It does not load
plugins, audio, or a playable project. Musical event meanings remain hypotheses
documented in analysis/FLP_FORMAT.md. Unknown chunks and event payloads survive
an unchanged read/write cycle, including noncanonical length prefixes of up to
five bytes. The five-byte bound is a local parser policy, not a verified limit
of FL Studio's reader.

Run from the reconstruction directory:
    python3 -m veggie_loops.flp inspect '/path/to/factory-template.flp'
    python3 -m veggie_loops.flp roundtrip source.flp new-output.flp
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import struct
from typing import Iterator


UINT32_MAX = (1 << 32) - 1
MAX_LENGTH_PREFIX_BYTES = 5


class FLPError(ValueError):
    """Invalid or unsupported framing, with an absolute byte offset."""

    def __init__(self, message: str, offset: int):
        self.offset = offset
        super().__init__(f"{message} at byte {offset} (0x{offset:x})")


def fixed_width(event_id: int) -> int | None:
    """Return the observed fixed payload width, or None for length framing."""
    if not 0 <= event_id <= 255:
        raise ValueError("event ID must be in 0..255")
    return (1, 2, 4)[event_id // 64] if event_id < 192 else None


def encode_length(length: int) -> bytes:
    """Encode a canonical unsigned 7-bit continuation length."""
    if not 0 <= length <= UINT32_MAX:
        raise ValueError("event length must fit an unsigned 32-bit integer")
    result = bytearray()
    while length >= 128:
        result.append((length & 127) | 128)
        length >>= 7
    result.append(length)
    return bytes(result)


def _read_length(data: bytes, offset: int, base_offset: int) -> tuple[int, int]:
    start = offset
    value = 0
    for index in range(MAX_LENGTH_PREFIX_BYTES):
        if offset == len(data):
            raise FLPError("truncated event length", base_offset + offset)
        octet = data[offset]
        offset += 1
        value |= (octet & 127) << (7 * index)
        if value > UINT32_MAX:
            raise FLPError("event length exceeds uint32", base_offset + start)
        if not octet & 128:
            return value, offset
    raise FLPError("event length prefix exceeds five bytes", base_offset + start)


@dataclass(frozen=True)
class Event:
    """An event ID and opaque payload; a parsed length prefix is retained."""

    event_id: int
    payload: bytes
    length_prefix: bytes | None = None
    offset: int | None = None

    @property
    def width(self) -> int | None:
        return fixed_width(self.event_id)

    def unsigned_value(self) -> int:
        """Interpret a fixed-width payload as little-endian, without semantics."""
        if self.width is None:
            raise ValueError("variable-length events have opaque payloads")
        if len(self.payload) != self.width:
            raise ValueError("fixed-width event has an invalid payload length")
        return int.from_bytes(self.payload, "little")

    def to_bytes(self) -> bytes:
        width = self.width
        if width is not None:
            if len(self.payload) != width:
                raise ValueError(f"event {self.event_id} requires {width} payload bytes")
            if self.length_prefix is not None:
                raise ValueError("fixed-width events cannot have a length prefix")
            return bytes((self.event_id,)) + self.payload
        prefix = self.length_prefix
        if prefix is None:
            prefix = encode_length(len(self.payload))
        else:
            length, consumed = _read_length(prefix, 0, 0)
            if consumed != len(prefix) or length != len(self.payload):
                raise ValueError("retained length prefix does not match the payload")
        return bytes((self.event_id,)) + prefix + self.payload


def parse_events(data: bytes, base_offset: int = 0) -> tuple[Event, ...]:
    """Decode complete event framing; never guess a payload's content."""
    result = []
    offset = 0
    while offset < len(data):
        start = offset
        event_id = data[offset]
        offset += 1
        width = fixed_width(event_id)
        prefix = None
        if width is None:
            prefix_start = offset
            length, offset = _read_length(data, offset, base_offset)
            prefix = data[prefix_start:offset]
        else:
            length = width
        end = offset + length
        if end > len(data):
            raise FLPError("event payload exceeds data chunk", base_offset + start)
        result.append(Event(event_id, data[offset:end], prefix, base_offset + start))
        offset = end
    return tuple(result)


@dataclass(frozen=True)
class Chunk:
    """A four-byte chunk tag and either opaque bytes or decoded FLdt events."""

    tag: bytes
    data: bytes | tuple[Event, ...]

    def __post_init__(self) -> None:
        if len(self.tag) != 4:
            raise ValueError("chunk tag must contain exactly four bytes")
        if self.tag == b"FLdt":
            if not isinstance(self.data, tuple) or any(
                not isinstance(event, Event) for event in self.data
            ):
                raise ValueError("FLdt chunks require a tuple of Event instances")
        elif not isinstance(self.data, bytes):
            raise ValueError("other chunks require opaque bytes")

    @property
    def payload(self) -> bytes:
        if isinstance(self.data, bytes):
            return self.data
        return b"".join(event.to_bytes() for event in self.data)

    def to_bytes(self) -> bytes:
        payload = self.payload
        if len(payload) > UINT32_MAX:
            raise ValueError("chunk payload exceeds uint32 length")
        return self.tag + struct.pack("<I", len(payload)) + payload


@dataclass(frozen=True)
class Header:
    """Raw header words; field names beyond word zero remain inferred."""

    format_word: int
    channel_count_candidate: int
    ppq_candidate: int
    extension: bytes = b""


@dataclass(frozen=True)
class FLPFile:
    chunks: tuple[Chunk, ...]

    def __post_init__(self) -> None:
        if not self.chunks or self.chunks[0].tag != b"FLhd":
            raise ValueError("the first chunk must be FLhd")
        if len(self.chunks[0].payload) < 6:
            raise ValueError("the header must contain at least three 16-bit words")
        if not any(chunk.tag == b"FLdt" for chunk in self.chunks):
            raise ValueError("at least one FLdt chunk is required")

    @property
    def header(self) -> Header:
        payload = self.chunks[0].payload
        return Header(*struct.unpack_from("<HHH", payload), payload[6:])

    def iter_events(self) -> Iterator[Event]:
        for chunk in self.chunks:
            if chunk.tag == b"FLdt":
                yield from chunk.data

    def to_bytes(self) -> bytes:
        return b"".join(chunk.to_bytes() for chunk in self.chunks)

    def summary(self) -> dict:
        """Return structural counts only, with no retained proprietary payloads."""
        encoded = self.to_bytes()
        events = tuple(self.iter_events())
        histogram = Counter(event.event_id for event in events)
        variable_lengths = Counter(
            len(event.length_prefix or encode_length(len(event.payload)))
            for event in events if event.width is None
        )
        note_lengths = Counter(len(event.payload) for event in events if event.event_id == 224)
        channel_markers = [event.unsigned_value() for event in events if event.event_id == 64]
        header = self.header
        return {
            "bytes": len(encoded),
            "sha256": hashlib.sha256(encoded).hexdigest(),
            "header": {
                "format_word": header.format_word,
                "channel_count_candidate": header.channel_count_candidate,
                "ppq_candidate": header.ppq_candidate,
                "extension_bytes": len(header.extension),
            },
            "chunks": [{"tag_hex": chunk.tag.hex(), "payload_bytes": len(chunk.payload)} for chunk in self.chunks],
            "event_count": len(events),
            "event_histogram": dict(sorted(histogram.items())),
            "length_prefix_width_histogram": dict(sorted(variable_lengths.items())),
            "event_64_values_match_0_to_header_count_minus_1": channel_markers == list(range(header.channel_count_candidate)),
            "event_224_payload_length_histogram": dict(sorted(note_lengths.items())),
            "event_224_payloads_divisible_by_24": all(length % 24 == 0 for length in note_lengths),
            "event_224_candidate_record_count": sum(length // 24 * count for length, count in note_lengths.items() if length % 24 == 0),
        }


def parse(data: bytes) -> FLPFile:
    """Parse chunk and event framing with exact bounds checking."""
    if not isinstance(data, bytes):
        raise TypeError("parse requires immutable bytes")
    offset = 0
    chunks = []
    while offset < len(data):
        start = offset
        if len(data) - offset < 8:
            raise FLPError("truncated chunk header", offset)
        tag = data[offset:offset + 4]
        size = struct.unpack_from("<I", data, offset + 4)[0]
        offset += 8
        if not chunks and tag != b"FLhd":
            raise FLPError("expected FLhd as first chunk", start)
        end = offset + size
        if end > len(data):
            raise FLPError("chunk payload exceeds file", start)
        payload = data[offset:end]
        if not chunks and len(payload) < 6:
            raise FLPError("FLhd requires at least six bytes", start)
        chunks.append(Chunk(tag, parse_events(payload, offset) if tag == b"FLdt" else payload))
        offset = end
    if not chunks:
        raise FLPError("empty file", 0)
    if not any(chunk.tag == b"FLdt" for chunk in chunks):
        raise FLPError("missing FLdt chunk", len(data))
    return FLPFile(tuple(chunks))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="vl-studio",
        description="Veggie Loops / VL Studio: inspect FLP structure and preserve project bytes.",
    )
    commands = parser.add_subparsers(dest="command", required=True)
    inspect_command = commands.add_parser("inspect", help="print structural JSON")
    inspect_command.add_argument("source", type=Path)
    roundtrip_command = commands.add_parser("roundtrip", help="write and verify an unchanged byte copy")
    roundtrip_command.add_argument("source", type=Path)
    roundtrip_command.add_argument("destination", type=Path)
    args = parser.parse_args(argv)
    try:
        source = args.source.read_bytes()
        project = parse(source)
        rebuilt = project.to_bytes()
        if rebuilt != source:
            raise ValueError("internal framing roundtrip mismatch")
        if args.command == "inspect":
            result = project.summary()
            result["source"] = str(args.source.resolve())
            print(json.dumps(result, indent=2))
        else:
            with args.destination.open("xb") as output:
                output.write(rebuilt)
            print(json.dumps({"destination": str(args.destination.resolve()), "bytes": len(rebuilt), "sha256": hashlib.sha256(rebuilt).hexdigest(), "byte_identical": True}))
        return 0
    except (OSError, ValueError, TypeError) as error:
        parser.exit(2, f"error: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
