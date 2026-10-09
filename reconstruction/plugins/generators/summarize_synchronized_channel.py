#!/usr/bin/env python3
"""Bind the bounded synchronized active voice channel integration to exact sources and targets."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_synchronized_channel.h", "three_osc_synchronized_channel.cpp", "test_three_osc_synchronized_channel.mm",
           "verify-synchronized-channel.sh", "summarize_synchronized_channel.py", "SYNCHRONIZED_CHANNEL.md",
           "three_osc_wrapper_core.h", "three_osc_wrapper_core.cpp", "three_osc_engine.cpp",
           "three_osc.hpp", "three_osc_tables.hpp", "three_osc_declick.hpp", "three_osc_declick.cpp",
           "three_osc_envelope.hpp", "three_osc_gain_mix.hpp", "three_osc_voice_output.hpp",
           "three_osc_legacy_tables.hpp", "three_osc_legacy_tables.cpp",
           "three_osc_envelope_coefficients.hpp", "three_osc_modulation.hpp",
           "three_osc_filter.hpp", "three_osc_filter_routing.hpp",
           "three_osc_voice_lifecycle.h", "three_osc_voice_lifecycle.cpp",
           "three_osc_sync_lfo.h", "three_osc_sync_lfo.cpp"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "synchronized-channel",
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
        "owned_channel_core_and_voices": True,
        "prepared_modulation_type0_filter_release_slew_accumulation_integrated": True,
        "ordinary_and_quick_release_transitions_integrated": True,
        "soft_polyphony_selection_and_ordered_completion_notifications": True,
        "nonzero_host_output_overwrite_differential_replay": True,
        "native_fruity_factory_rebuilt": False,
        "actual_host_scheduling_rebuilt": False,
        "host_time_signature_context_delivery_rebuilt": False,
        "synchronized_lfo_metadata_and_audio_integrated": True,
        "release_refresh_audio_application_integrated": True,
        "actual_host_clock_production_rebuilt": False,
        "filter_mode_switching_rebuilt": False,
        "gui_rebuilt": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Fixed type0 filter, circular pan law0 and public filter-mode113=0. Group flags0..63 and enabled-volume changes are replayed live.",
        "Six fixed rate/tempo pairs each cross six explicit PPQs. Live rate/tempo/PPQ changes and actual host delivery/scheduling remain open; live group flags and volume-enabled controls are compared.",
        "Deterministic waveform controls0..4, default inversion/ring/random phase, HQ/legacy and initial44100Hz/441-sample release context.",
        "Borrowed final pitch is reset by the caller and automated in[-2400,2400] per block, with final ModX/ModY in[-.25,.25].",
        "Controlled nonthrowing host callback records ordered VoiceKill(tag,-1); deletion is explicit after render. Reentrant deletion and actual host timing are not proven.",
        "Native cleanup is explicit when the model destroys still-owned voices; new API RAII cleanup is not original destruction-ownership equivalence.",
        "Finite working pipeline outputs/history/gains extend isolated prepared domains without arbitrary-history/amplitude equivalence.",
        "Valid pointer lifetime, finite[-1,1] tables, output nonoverlap and serial access across all raw-engine instances remain preconditions.",
        "Own API invalid times/frames/configuration/pitch reject with preserved observed state and output; invalid original calls and injected allocation failures/unwind are excluded.",
        "Controlled host MixingTime/GT_Ticks pairs use finite[-2^63,2^63) ticks; this is not application clock production. Internal cfg+0x334 dirty is separate from public113 at+0x330.",
        "Pre-render volume-stage6 refresh candidates are counted from native state and dirty/disabled-volume predicates, not instrumented callback counts.",
        "Cross-channel global contexts, other filter/raw modes, actual application synchronized clock production, native factory/state/editor ABI, actual host/project execution and full Fruity/VST/AU equivalence remain open.",
    ],
})
(here / "synchronized-channel-verification.json").write_text(json.dumps(result, indent=2) + "\n")
