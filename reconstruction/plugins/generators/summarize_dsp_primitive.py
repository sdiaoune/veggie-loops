#!/usr/bin/env python3
"""Bind a sanitized primitive replay result to exact original-source files."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
module, result_path, artifact_path = sys.argv[1:]
modules = {
    "envelope": ["three_osc_envelope.hpp", "three_osc_envelope.cpp", "test_three_osc_envelope.mm", "verify-envelope.sh"],
    "envelope-coefficients": ["three_osc_envelope.hpp", "three_osc_envelope_coefficients.hpp", "three_osc_envelope_coefficients.cpp", "test_three_osc_envelope_coefficients.mm", "verify-envelope-coefficients.sh"],
    "legacy-tables": ["three_osc_legacy_tables.hpp", "three_osc_legacy_tables.cpp", "test_three_osc_legacy_tables.mm", "verify-legacy-tables.sh"],
}
sources = modules[module] + ["summarize_dsp_primitive.py"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(pathlib.Path(result_path).read_text())
result.update({
    "module": module,
    "source_sha256": {name: digest(here / name) for name in sources},
    "compiled_dylib_sha256": digest(pathlib.Path(artifact_path)),
    "reviewed_native_target": {
        "name": "installed 3x Osc Fruity wrapper",
        "universal_sha256": "c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c",
        "arm64_sha256": "bd5070df788f4c5ab88d7ed912951866682b0b318ff13f6d9e9936ea036a6e27",
        "fixture_architecture_guard": "macOS arm64 only",
    },
    "scope": {
        "new_c_abi": True,
        "native_fruity_factory_rebuilt": False,
        "host_tick_context_production_rebuilt": False,
        "voice_pipeline_integrated": False,
        "filter_and_final_mixer_rebuilt": False,
        "gui_rebuilt": False,
        "fl_vst_au_host_equivalence": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Prepared-domain/normal-call arithmetic only; see header ranges and table/buffer ownership.",
        "Native wrapper is an identity-bound read-only oracle, not a dependency of the compiled primitive.",
        "Isolated primitive equivalence does not establish complete wrapper, plugin, VST or AU equivalence.",
        "Native GUI/object-allocation/unwind/invalid-input behavior remains outside this component.",
    ],
})
(here / (module + "-verification.json")).write_text(json.dumps(result, indent=2) + "\n")
