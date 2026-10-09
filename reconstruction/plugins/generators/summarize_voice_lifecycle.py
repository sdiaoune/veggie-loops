#!/usr/bin/env python3
"""Bind the bounded voice lifecycle metadata to exact sources and targets."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_voice_lifecycle.h", "three_osc_voice_lifecycle.cpp",
           "test_three_osc_voice_lifecycle.mm", "verify-voice-lifecycle.sh",
           "summarize_voice_lifecycle.py", "VOICE_LIFECYCLE.md"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "voice-lifecycle",
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
        "metadata_only": True,
        "actual_factory_trigger_release_kill_render_metadata_replay": True,
        "controlled_host_completion_notifications": True,
        "native_fruity_factory_rebuilt": False,
        "actual_host_scheduling_rebuilt": False,
        "active_envelope_state_rebuilt_by_this_module": False,
        "audio_rebuilt_by_this_module": False,
        "integrated_with_prepared_voice_composer": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "Default native editor controls, HQ rendering and actual441-sample initial release context.",
        "Soft polyphony selection marks an existing voice but neither deletes it nor prevents a new trigger.",
        "Controlled host shim records ordered VoiceKill(tag,-1) requests and explicitly removes voices after GenRender; real host timing and reentrant deletion remain open.",
        "Direct quick-release/advance helpers use controlled metadata in live original editor objects; arbitrary injected fields are not host-production evidence.",
        "Ordinary-release metadata is tested with default disabled volume envelopes. Active envelope-stage changes are outside this module.",
        "Generic completion lengths and the thin API's wider metadata preconditions are generalizations beyond the actual factory release context.",
        "Output finite/guard checks do not constitute reconstructed-audio comparison in this metadata fixture.",
        "Native object allocation/lifetime ABI, invalid-call/failure behavior, host clocks, composer integration, state/editor/factory and full Fruity/VST/AU equivalence remain open.",
    ],
})
(here / "voice-lifecycle-verification.json").write_text(json.dumps(result, indent=2) + "\n")
