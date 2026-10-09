#!/usr/bin/env python3
"""Bind the live-class builder corpus to its independent source dependencies."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
work = pathlib.Path(sys.argv[1])
files = ["live_compressor.h", "live_compressor.hpp", "live_compressor.cpp",
         "test_live_compressor.mm", "test_allocation_failure.cpp", "verify.sh",
         "README.md", "summarize.py", "../peak_compressor.h", "../peak_compressor.cpp",
         "../rms_compressor.h", "../rms_compressor.cpp"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
report = {
    "schema_version": 1,
    "component": "Purity independently written live compressor C++ classes",
    "status": "builder_native_differential_passed_pending_independent_review",
    "source_sha256": {name: digest(here / name) for name in files},
    "target": {
        "universal_sha256": "ef2675ee69f9498ae10807820660e1158ba3c50684f44dea46b03efd7ceb1b07",
        "arm64_sha256": "f05490472c0c170b99caa93ce9efa41eb712035bb253d53c29909ea00bc8816f",
        "native_fixture_architecture": "Apple arm64",
    },
    "compiled_library_sha256": digest(work / "libvl_purity_live.dylib"),
    "native_comparison": json.loads((work / "result.json").read_text()),
    "source_allocation_failures": json.loads((work / "allocation-result.json").read_text()),
    "scope": {
        "live_cpp_classes": True,
        "peak_object_bytes": 64,
        "rms_object_bytes": 72,
        "virtual_slots_including_destructors": 16,
        "own_bounded_c_factory_control_api": True,
        "original_native_factory_symbols_exported": False,
        "full_purity_plugin_recompiled": False,
        "editor_state_midi_vst_au_host_equivalence": False,
        "realtime_certification": False,
    },
    "sanitizers": {
        "new_library_and_both_fixtures": ["AddressSanitizer", "UndefinedBehaviorSanitizer"],
        "original_commercial_library_instrumented": False,
    },
    "limitations": [
        "Finite serialized caller domain; valid buffer/storage and default FP/libc formatting environment.",
        "Native undefined padding/gain/detector at disabled construction are independently initialized and excluded from native-defined comparison.",
        "Atomic replacement failure preserves old history, extending the original delete-first factory failure behavior.",
        "The full application tIFX descriptor/chain, plugin state, native class/factory identities, editor, MIDI, VST/AU and RT behavior remain unproved.",
    ],
    "independent_review": {"status": "pending"},
}
(here / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
