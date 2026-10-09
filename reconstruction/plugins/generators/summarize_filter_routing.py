#!/usr/bin/env python3
"""Bind prepared filter-routing replay to exact original source and targets."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_filter_routing.hpp", "three_osc_filter_routing.cpp", "test_three_osc_filter_routing.mm",
           "verify-filter-routing.sh", "summarize_filter_routing.py", "FILTER_ROUTING.md",
           "three_osc_filter.hpp", "three_osc_voice_output.hpp"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "filter-routing",
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
        "prepared_filter_activation_slew_double_order_verified": True,
        "native_factory_context_production_rebuilt": False,
        "actual_host_editor_routing_rebuilt": False,
        "full_voice_audio_pipeline_integrated": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Finite prepared-state/control/buffer/gain domain only; routing/kernel headers specify exact preconditions.",
        "Native comparison uses synthetic voice/context/property/buffer layouts and controlled rate context rather than original constructors or an actual host.",
        "Types0..7, raw controls0..256, combined normalized values[-2,2], finite input magnitude<=1, zero initial histories and1..4096frames only.",
        "The routing corpus independently covers larger carried history (observed magnitude130936), extending the standalone kernel corpus's initial-history<=2 scope; no arbitrary initial-history bound is proved.",
        "Each retained-state fixture fixes type/doubleOrder/rate. Live changes to these modes/rate and native history reset/configuration routing remain unproved.",
        "Native mode/property mappings, context production, editor control dispatch/configuration updates, general design type8 and full voice audio integration remain open.",
        "No commercial assets or binaries are embedded; this is not complete Fruity/VST/AU/FL equivalence.",
    ],
})
(here / "filter-routing-verification.json").write_text(json.dumps(result, indent=2) + "\n")
