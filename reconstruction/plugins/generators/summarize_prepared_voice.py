#!/usr/bin/env python3
"""Bind the bounded prepared active voice integration to exact sources and targets."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_prepared_voice.h", "three_osc_prepared_voice.cpp", "test_three_osc_prepared_voice.mm",
           "verify-prepared-voice.sh", "summarize_prepared_voice.py", "PREPARED_VOICE.md",
           "three_osc_wrapper_core.h", "three_osc_wrapper_core.cpp", "three_osc_engine.cpp",
           "three_osc.hpp", "three_osc_tables.hpp", "three_osc_declick.hpp", "three_osc_declick.cpp",
           "three_osc_envelope.hpp", "three_osc_gain_mix.hpp", "three_osc_voice_output.hpp",
           "three_osc_legacy_tables.hpp", "three_osc_legacy_tables.cpp",
           "three_osc_envelope_coefficients.hpp", "three_osc_modulation.hpp",
           "three_osc_filter.hpp", "three_osc_filter_routing.hpp"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "prepared-voice",
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
        "prepared_five_group_modulation_single_filter_voice_pipeline": True,
        "actual_native_factory_GenRender_differential_replay": True,
        "native_fruity_factory_rebuilt": False,
        "actual_host_voice_notifications_integrated": False,
        "host_tick_context_production_rebuilt": False,
        "synchronized_lfo_rebuilt": False,
        "filter_mode_switching_rebuilt": False,
        "gui_rebuilt": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Fixed type0 filter, observed circular master pan law0, controlled host pan callback, global113=0 and no synchronized LFO flag32.",
        "Six fixed rate/tempo pairs, each crossed with six explicit PPQs delivered through dispatcher14 SetTimeSig Value+8; live context changes and actual host time-signature/context delivery remain open.",
        "Native replay covers deterministic oscillator waveforms0..4, random-phase0, default inversion/ring switches, HQ/legacy and initial44100Hz release context.",
        "Other initializer rates/oscillator modes are independent generalizations, not additional native pipeline evidence.",
        "Final pitch automation is replayed in[-2400,2400] cents; callers reset base final pitch before each block.",
        "Carried type0 filter history and measured finite working samples/gains extend smaller isolated primitive corpora, without an arbitrary-history or arbitrary-amplitude proof.",
        "Two live voices render in creation order into positive zero. The original final host write overwrites output. This existing corpus used zero host destinations; nonzero-destination overwrite has a separate channel regression and remains outside this accumulation API.",
        "Original host-kill callbacks are no-ops; final native cleanup is explicit. Voice stealing and application voice notifications remain open.",
        "Borrowed raw core/voice and readable finite[-1,1] LFO tables outlive the composer. Caller serializes all raw-engine instances sharing factory/RNG state.",
        "Rejection-preservation checks concern the new C API, not invalid-call equivalence with the original. No injected allocation-failure/unwind proof.",
        "Native factory/state/editor ABI, actual host time-signature/context delivery and project execution, live application rendering and complete Fruity/VST/AU equivalence remain open.",
    ],
})
(here / "prepared-voice-verification.json").write_text(json.dumps(result, indent=2) + "\n")
