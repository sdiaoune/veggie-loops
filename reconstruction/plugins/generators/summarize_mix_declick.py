#!/usr/bin/env python3
"""Sanitize and bind isolated gain/declick evidence to exact original source."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
module, result_path, artifact_path = sys.argv[1:]
modules = {
    "gain-mix": ["three_osc_gain_mix.hpp", "three_osc_gain_mix.cpp", "test_three_osc_gain_mix.mm", "verify-gain-mix.sh"],
    "declick": ["three_osc_envelope.hpp", "three_osc_declick.hpp", "three_osc_declick.cpp", "test_three_osc_declick.mm", "verify-declick.sh"],
}
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(pathlib.Path(result_path).read_text())
result.update({
    "module": module,
    "source_sha256": {name: digest(here / name) for name in modules[module] + ["summarize_mix_declick.py", "MIX_DECLICK.md"]},
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
        "voice_pipeline_integrated": False,
        "filter_rebuilt": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Normal prepared-domain serial calls only; headers specify arithmetic and buffer preconditions.",
        "The original wrapper is a read-only oracle; no native asset bytes or commercial DSP library is embedded.",
        "Two isolated stereo accumulation routines and precomputed release/table arithmetic are not complete final voice DSP.",
        "Native allocation/unwind/invalid inputs, GUI, host routing and complete generator/VST/AU equivalence remain open.",
    ],
})
if module == "declick":
    result["native_generation_count_verified"] = 64
    result["other_generation_counts_are_independent_generalization"] = True
    result["reviewed_native_vector_dependency"] = {
        "name": "dsp_ippv2_x64.dylib",
        "universal_sha256": "f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1",
        "arm64_sha256": "72a166d85676bc317bc3556b88f2eddb30fd955156bf8fbd696cb5de847aa1b3",
        "reconstructed_system_calls": ["vvcosf", "vvexpf", "vDSP_vsmul", "vDSP_vsadd"],
        "runtime_dependency_of_rebuilt_module": False,
    }
    result["limitations"].append("Mode1/2, dynamic 64-sample cache, native table-object lifecycle and allocator failure are not implemented. macOS Accelerate is required for the exact replay.")
(here / (module + "-verification.json")).write_text(json.dumps(result, indent=2) + "\n")
