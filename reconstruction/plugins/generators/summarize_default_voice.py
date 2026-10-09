#!/usr/bin/env python3
"""Bind the bounded default voice integration to exact sources and targets."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_default_voice.h", "three_osc_default_voice.cpp", "test_three_osc_default_voice.mm",
           "verify-default-voice.sh", "summarize_default_voice.py", "DEFAULT_VOICE.md",
           "three_osc_wrapper_core.h", "three_osc_wrapper_core.cpp", "three_osc_engine.cpp",
           "three_osc.hpp", "three_osc_tables.hpp", "three_osc_declick.hpp", "three_osc_declick.cpp",
           "three_osc_envelope.hpp", "three_osc_gain_mix.hpp", "three_osc_voice_output.hpp",
           "three_osc_legacy_tables.hpp", "three_osc_legacy_tables.cpp"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "default-voice",
    "source_sha256": {name: digest(here / name) for name in sources},
    "compiled_dylib_sha256": digest(artifact_path),
    "reviewed_native_targets": [
        {"name": "3x Osc Fruity wrapper", "universal_sha256": "c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c", "arm64_sha256": "bd5070df788f4c5ab88d7ed912951866682b0b318ff13f6d9e9936ea036a6e27"},
        {"name": "3x Osc engine.dylib", "universal_sha256": "d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f", "arm64_sha256": "c90d11fe12c86d620aabd135078c7cca49cc2b007b0c750e0db63a1e7508db48"},
        {"name": "dsp_ippv2_x64.dylib", "universal_sha256": "f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1", "arm64_sha256": "72a166d85676bc317bc3556b88f2eddb30fd955156bf8fbd696cb5de847aa1b3"},
    ],
    "fixture_architecture_guard": "macOS arm64 only",
    "scope": {
        "new_c_abi": True,
        "default_no_filter_no_modulation_voice_output_integrated": True,
        "native_fruity_factory_rebuilt": False,
        "actual_host_voice_notifications_integrated": False,
        "host_tick_context_production_rebuilt": False,
        "filter_modes_rebuilt": False,
        "envelope_lfo_modulation_pipeline_rebuilt": False,
        "gui_rebuilt": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Default integrated-editor controls, final ModX/ModY=0, observed circular master pan law0 only.",
        "Native replay covers deterministic waveform controls0..4, oscillator random-phase0, HQ and legacy paths, and an initial44100Hz release context.",
        "Other initializer rates/oscillator modes are independent generalizations, not additional native pipeline evidence.",
        "Native pipeline replay uses static note pitches in[-2400,2400] cents. The API's broader[-9600,9600] range and mid-note pitch automation are not covered by this corpus.",
        "Two live voices render in creation order into a positive-zero accumulator. The original final host write overwrites output. This existing corpus used zero host destinations; nonzero-destination overwrite has a separate channel regression and remains outside this accumulation API.",
        "The original host pan callback is controlled by the fixture, and original host-kill callbacks are no-ops; final native cleanup is explicit.",
        "Borrowed raw core/voice must outlive the output object; caller pairs core and output sample-rate updates and serializes accesses across every raw-engine instance sharing factory/RNG state.",
        "Native factories, invalid-call equivalence, allocation failures/unwind, voice stealing/host routing, modulation, filters, GUI and complete VST/AU/FL equivalence remain open.",
    ],
})
(here / "default-voice-verification.json").write_text(json.dumps(result, indent=2) + "\n")
