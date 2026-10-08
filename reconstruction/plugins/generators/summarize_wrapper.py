#!/usr/bin/env python3
"""Publish sanitized source/target identity and bounded wrapper test scope."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result = json.loads(pathlib.Path(sys.argv[1]).read_text())
sources = [
    "three_osc.hpp", "three_osc_tables.hpp", "three_osc_engine.cpp",
    "three_osc_wrapper_core.h", "three_osc_wrapper_core.cpp",
    "test_three_osc_wrapper_core.mm", "verify-wrapper-core.sh",
    "verify_wrapper.sh", "summarize_wrapper.py", "WRAPPER_CORE.md",
]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result.update({
    "module": "114-control storage, version-14 preset, raw HQ/legacy wrapper core",
    "source_files": {name: digest(here / name) for name in sources},
    "built_library_sha256": digest(pathlib.Path(sys.argv[2])),
    "reviewed_native_targets": {
        "wrapper": {
            "universal_sha256": "c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c",
            "arm64_sha256": "bd5070df788f4c5ab88d7ed912951866682b0b318ff13f6d9e9936ea036a6e27",
        },
        "engine": {
            "universal_sha256": "d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f",
            "arm64_sha256": "c90d11fe12c86d620aabd135078c7cca49cc2b007b0c750e0db63a1e7508db48",
        },
    },
    "scope": {
        "control_storage_slots": 114, "oscillator_controls": 21,
        "editor_group_fields": 85, "editor_globals": 3, "reserved_control_slots": 5,
        "preset_payload_bytes": 456, "preserved_field_bytes": 441,
        "canonical_reserved_zero_bytes": 12, "undefined_native_padding_bytes": 3,
        "new_c_abi": True, "native_fruity_factory_implemented": False,
        "integrated_editor_modulation_dsp_implemented": False,
        "integrated_editor_envelope_dsp_implemented": False,
        "final_generator_mixing_implemented": False,
        "voice_stealing_implemented": False, "gui_implemented": False,
        "old_preset_versions_implemented": False,
        "fl_vst_au_host_integration_verified": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Normal valid serial calls and bounded corpora only; invalid/allocator/unwind behavior differs.",
        "Host pan law and legacy waveform tables are caller-supplied; corpus uses synthetic inputs.",
        "Pascal RNG fixture is read from native once per case; model alone is initialized from it.",
        "Independent small-engine noise globals are synchronized before each render block.",
        "Control storage/state equivalence does not reconstruct integrated-editor modulation DSP.",
        "The native factory is an oracle; the rebuilt library exposes a separate bounded C ABI.",
    ],
})
(here / "wrapper-core-verification.json").write_text(json.dumps(result, indent=2) + "\n")
