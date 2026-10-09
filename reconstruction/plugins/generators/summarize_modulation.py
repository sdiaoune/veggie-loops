#!/usr/bin/env python3
"""Sanitize the prepared modulation state replay and bind source identities."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_modulation.hpp", "three_osc_modulation.cpp", "test_three_osc_modulation.mm",
           "verify-modulation.sh", "summarize_modulation.py", "MODULATION.md",
           "three_osc_envelope.hpp", "three_osc_envelope_coefficients.hpp"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "modulation",
    "source_sha256": {name: digest(here / name) for name in sources},
    "compiled_dylib_sha256": digest(artifact_path),
    "reviewed_native_target": {
        "name": "3x Osc Fruity wrapper",
        "universal_sha256": "c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c",
        "arm64_sha256": "bd5070df788f4c5ab88d7ed912951866682b0b318ff13f6d9e9936ea036a6e27",
        "fixture_architecture_guard": "macOS arm64 only",
    },
    "scope": {
        "new_c_abi": True,
        "prepared_five_group_modulation_state_verified": True,
        "native_object_lifecycle_rebuilt": False,
        "host_tick_production_rebuilt": False,
        "audio_pipeline_integrated": False,
        "filter_rebuilt": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Prepared configurations/initialized states/readable tables and explicit host tick conditions only; successful coefficient preconditions apply.",
        "Each LFO table has16384 readable finite samples in[-1,1], matching the controlled sine-table corpus.",
        "Native comparison uses synthetic object layouts and controlled tables, rather than an original factory or actual host clock call.",
        "Raw depth[-128,128] and finite final pitch magnitude<=24000; wider native editor depth controls remain unproved.",
        "Constructor/lifecycle, automatic host timing, configuration update routing, voice limit/stealing, filtering, samples and audio pipeline integration remain open.",
        "No native assets or commercial binaries are embedded; this component does not establish complete Fruity/VST/AU/FL equivalence.",
    ],
})
(here / "modulation-verification.json").write_text(json.dumps(result, indent=2) + "\n")
