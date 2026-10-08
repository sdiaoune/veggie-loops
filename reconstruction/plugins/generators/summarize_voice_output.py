#!/usr/bin/env python3
"""Bind a sanitized voice-output replay result to the reviewed source."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_voice_output.hpp", "three_osc_voice_output.cpp",
           "test_three_osc_voice_output.mm", "verify-voice-output.sh",
           "summarize_voice_output.py", "VOICE_OUTPUT.md"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "voice-output",
    "source_sha256": {name: digest(here / name) for name in sources},
    "compiled_dylib_sha256": digest(artifact_path),
    "reviewed_native_target": {
        "name": "installed 3x Osc Fruity wrapper",
        "universal_sha256": "c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c",
        "arm64_sha256": "bd5070df788f4c5ab88d7ed912951866682b0b318ff13f6d9e9936ea036a6e27",
        "fixture_architecture_guard": "macOS arm64 only",
    },
    "scope": {
        "new_c_abi": True,
        "native_fruity_factory_rebuilt": False,
        "host_pan_preference_routing_rebuilt": False,
        "voice_pipeline_integrated": False,
        "filter_and_final_mixer_rebuilt": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Finite prepared-domain normal-call arithmetic only; header preconditions apply to both C entry points.",
        "The circular whole helper uses the observed native law 0. The linear primitive uses the separately observed compensation.",
        "Darwin joint sin/cos results are verified; other platform math implementations are not native-equivalence evidence.",
        "The installed wrapper is a read-only oracle and is not embedded in or required by the compiled primitives.",
        "Plugin factory, GUI, invalid-input handling, filters, final audio mixing and actual host preference routing remain open.",
    ],
})
(here / "voice-output-verification.json").write_text(json.dumps(result, indent=2) + "\n")
