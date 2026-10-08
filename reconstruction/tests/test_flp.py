"""Original synthetic framing tests; no FL Studio project payloads are copied."""

from dataclasses import replace
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import struct
import tempfile
import unittest

from veggie_loops.flp import Chunk, Event, FLPError, FLPFile, encode_length, main, parse, parse_events


def chunk(tag: bytes, payload: bytes) -> bytes:
    return tag + struct.pack("<I", len(payload)) + payload


def synthetic_file(events: bytes = b"", extension: bytes = b"") -> bytes:
    return chunk(b"FLhd", struct.pack("<HHH", 0, 2, 96) + extension) + chunk(b"FLdt", events)


class FramingTests(unittest.TestCase):
    def test_all_width_boundaries_and_empty_blob_roundtrip(self):
        events = (
            Event(0, b"\x11"), Event(63, b"\x22"),
            Event(64, b"\x34\x12"), Event(127, b"\x45\x23"),
            Event(128, b"\x78\x56\x34\x12"), Event(191, b"\xff" * 4),
            Event(192, b""), Event(255, b"\x01\x00\xff"),
        )
        original = synthetic_file(b"".join(event.to_bytes() for event in events))
        result = parse(original)
        self.assertEqual(result.to_bytes(), original)
        parsed = tuple(result.iter_events())
        self.assertEqual([e.payload for e in parsed], [e.payload for e in events])
        self.assertEqual(parsed[2].unsigned_value(), 0x1234)
        self.assertEqual(parsed[4].unsigned_value(), 0x12345678)
        self.assertEqual(parsed[0].offset, 22)
        self.assertEqual(result.header.ppq_candidate, 96)

    def test_length_transition_boundaries(self):
        for length in (0, 127, 128, 16383, 16384):
            with self.subTest(length=length):
                event = Event(200, b"Z" * length)
                result = parse_events(event.to_bytes())
                self.assertEqual(result[0].payload, event.payload)
                self.assertEqual(result[0].length_prefix, encode_length(length))

    def test_noncanonical_length_prefix_is_preserved(self):
        original = synthetic_file(b"\xc8\x81\x00A\xff\x80\x00")
        result = parse(original)
        self.assertEqual(result.to_bytes(), original)
        self.assertEqual(tuple(result.iter_events())[0].length_prefix, b"\x81\x00")

    def test_unknown_chunks_multiple_data_chunks_and_header_extension(self):
        original = synthetic_file(b"\x3f\x01", b"EXT") + chunk(b"????", b"opaque") + chunk(b"FLdt", b"\xc0\x00")
        result = parse(original)
        self.assertEqual(result.to_bytes(), original)
        self.assertEqual(result.header.extension, b"EXT")
        self.assertEqual([e.event_id for e in result.iter_events()], [63, 192])
        self.assertEqual(result.chunks[2].payload, b"opaque")

    def test_changed_payload_cannot_reuse_stale_length_prefix(self):
        event = parse_events(b"\xc0\x01A")[0]
        with self.assertRaises(ValueError):
            replace(event, payload=b"AB").to_bytes()
        self.assertEqual(replace(event, payload=b"AB", length_prefix=None).to_bytes(), b"\xc0\x02AB")

    def test_truncated_fixed_payloads_at_each_width(self):
        for event in (b"\x00", b"\x40\x00", b"\x80\x00\x00\x00"):
            with self.subTest(event=event), self.assertRaises(FLPError):
                parse(synthetic_file(event))

    def test_bad_or_truncated_length_framing(self):
        for event in (
            b"\xc0", b"\xc0\x80", b"\xc0\x03AB",
            b"\xc0\xff\xff\xff\xff\x10",
            b"\xc0\x80\x80\x80\x80\x80\x00",
        ):
            with self.subTest(event=event), self.assertRaises(FLPError):
                parse(synthetic_file(event))

    def test_malformed_chunk_and_header_cases(self):
        bad_files = (
            b"", b"FLhd", b"BAD!" + b"\x00" * 4,
            chunk(b"FLhd", b"\x00" * 5) + chunk(b"FLdt", b""),
            chunk(b"FLhd", b"\x00" * 6),
            synthetic_file() + b"tail",
            b"FLhd\xff\xff\xff\xff" + b"\x00" * 6,
        )
        for data in bad_files:
            with self.subTest(data=data), self.assertRaises(FLPError):
                parse(data)

    def test_each_truncated_prefix_of_complete_event_file_is_rejected(self):
        original = synthetic_file(Event(224, b"hello").to_bytes())
        for size in range(len(original)):
            with self.subTest(size=size), self.assertRaises(FLPError):
                parse(original[:size])

    def test_absolute_error_offset(self):
        with self.assertRaises(FLPError) as caught:
            parse(synthetic_file(b"\x40\x01"))
        self.assertEqual(caught.exception.offset, 22)

    def test_invalid_constructed_objects_are_rejected(self):
        for event in (Event(256, b""), Event(64, b""), Event(0, b"x", b"\x01")):
            with self.subTest(event=event), self.assertRaises(ValueError):
                event.to_bytes()
        with self.assertRaises(ValueError):
            Chunk(b"FLdt", b"unparsed")
        with self.assertRaises(ValueError):
            FLPFile((Chunk(b"FLhd", b"\x00" * 6),))

    def test_cli_inspect_returns_structural_json_without_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "synthetic.flp"
            source.write_bytes(synthetic_file(Event(255, b"opaque-secret-sample").to_bytes()))
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(main(["inspect", str(source)]), 0)
            result = json.loads(output.getvalue())
            self.assertEqual(result["source"], str(source.resolve()))
            self.assertEqual(result["event_histogram"], {"255": 1})
            self.assertNotIn("opaque-secret-sample", output.getvalue())

    def test_cli_roundtrip_writes_exact_bytes_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "synthetic.flp"
            destination = Path(directory) / "rebuilt.flp"
            original = synthetic_file(b"\xc8\x81\x00A")
            source.write_bytes(original)
            with redirect_stdout(io.StringIO()):
                self.assertEqual(main(["roundtrip", str(source), str(destination)]), 0)
            self.assertEqual(destination.read_bytes(), original)
            destination.write_bytes(b"keep-existing-data")
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
                main(["roundtrip", str(source), str(destination)])
            self.assertEqual(caught.exception.code, 2)
            self.assertEqual(destination.read_bytes(), b"keep-existing-data")


if __name__ == "__main__":
    unittest.main()
