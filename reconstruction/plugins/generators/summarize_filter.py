#!/usr/bin/env python3
"""Bind prepared filter replay results to exact source and native identities."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_filter.hpp", "three_osc_filter.cpp", "test_three_osc_filter.mm",
           "verify-filter.sh", "summarize_filter.py", "FILTER.md"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "filter",
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
        "prepared_single_biquad_special_kernels_verified": True,
        "native_context_production_rebuilt": False,
        "filter_activation_routing_rebuilt": False,
        "double_order_gain_compensation_rebuilt": False,
        "audio_pipeline_integrated": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Finite prepared-domain coefficients/history/buffers only; header preconditions apply.",
        "Initialized exponent/denormal context is explicitly checked; native context/preference production and actual host routing are not reconstructed.",
        "Native coefficient inputs[-2,2], render preparation[0,1], frames0..4096, seven rate contexts8000..384000Hz. Other rates/domains are unproved.",
        "Biquad coefficient type1..5 only; general design helper types6..8, filter activation, double-order compensation, lifecycle and voice audio integration remain open.",
        "No commercial binary or native assets are embedded, and no complete Fruity/VST/AU/FL equivalence is claimed.",
    ],
})
(here / "filter-verification.json").write_text(json.dumps(result, indent=2) + "\n")
