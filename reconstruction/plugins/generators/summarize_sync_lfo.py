#!/usr/bin/env python3
"""Bind the serial synchronized LFO metadata producer to exact inputs."""
import hashlib
import json
import pathlib
import sys

here = pathlib.Path(__file__).resolve().parent
result_path, artifact_path = map(pathlib.Path, sys.argv[1:])
sources = ["three_osc_sync_lfo.h", "three_osc_sync_lfo.cpp", "test_three_osc_sync_lfo.mm",
           "verify-sync-lfo.sh", "summarize_sync_lfo.py", "SYNC_LFO.md",
           "three_osc_legacy_tables.hpp", "three_osc_legacy_tables.cpp",
           "three_osc_envelope.hpp", "three_osc_envelope_coefficients.hpp"]
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = json.loads(result_path.read_text())
result.update({
    "module": "sync-lfo-metadata",
    "source_sha256": {name: digest(here / name) for name in sources},
    "compiled_dylib_sha256": digest(artifact_path),
    "reviewed_native_targets": [
        {"name": "3x Osc Fruity wrapper", "universal_sha256": "c4e64bada4f0e8866e8589cb6e7fd0586d83ec53de52491c6111d0bd9395805c", "arm64_sha256": "bd5070df788f4c5ab88d7ed912951866682b0b318ff13f6d9e9936ea036a6e27"},
        {"name": "3x Osc engine.dylib", "universal_sha256": "d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f", "arm64_sha256": "c90d11fe12c86d620aabd135078c7cca49cc2b007b0c750e0db63a1e7508db48"},
        {"name": "dsp_ippv2_x64.dylib", "universal_sha256": "f0a62121ba6e9fe38eb64a812adb3437a4204cbbc266bc95ff0aaf3df8a76cd1", "arm64_sha256": "72a166d85676bc317bc3556b88f2eddb30fd955156bf8fbd696cb5de847aa1b3"},
    ],
    "fixture_architecture_guard": "macOS arm64 only",
    "native_locations_arm64": {
        "editor_group_update_and_dirty_exchange": "0x95660 / 0x4d20; configuration+0x334",
        "public_filter_mode": "0x95660; configuration+0x330, parameter113, payload+452",
        "frame_dirty_consumption": "0x1bc3d0 / 0x4d60; context+0x24",
        "registry_rebuild": "0x1bc310; flags bit32 in five configuration groups",
        "unordered_registry_removal": "0x149e30; list+0x18 policy0",
        "public_NewTick": "0x5e910 -> 0x1bc770 -> 0x1bc690",
        "public_SongPosChanged": "0x5bcf0; dispatcher13, HostDispatcher36/index4",
        "mixing_time_conversion": "0x5c110 FCVTZS X0,D0; 0x5c114 low32 extraction",
        "phase_relocation": "0x1bc790 -> 0x1bc6f0 -> 0x6cf30 -> 0x4a78",
        "nonempty_frame_pending_clear": "0x1bc640; context+0x20",
    },
    "scope": {
        "new_serial_c_abi": True,
        "internal_dirty_latch_and_unordered_registration": True,
        "explicit_tick_and_song_position_phase_delivery": True,
        "empty_frame_retention_and_release_refresh_metadata": True,
        "actual_native_factory_public_callback_differential_replay": True,
        "actual_host_clock_production_rebuilt": False,
        "concurrent_atomic_or_allocating_native_list_abi_rebuilt": False,
        "synchronized_audio_pipeline_rebuilt": False,
        "release_refresh_audio_application_rebuilt": False,
        "native_fruity_factory_rebuilt": False,
        "gui_rebuilt": False,
        "full_plugin_recompiled": False,
    },
    "limitations": [
        "The internal dirty latch at configuration+0x334 is separate from public filter-mode parameter113 at+0x330. Registration depends on group flag32 and dirty consumption, not parameter113.",
        "All calls are serial on initialized valid state with five readable nonoverlapping flags/increments. This helper has no allocating registry or native atomic ABI.",
        "Prepared increments are compared using independently reconstructed coefficients for six tempos crossed with six explicit PPQs, fixed within each44100Hz fixture.",
        "Public SongPosChanged requests a controlled16-byte TFPTime through FHD_GetMixingTime/GT_Ticks; actual application clock production and scheduling remain open.",
        "Supported scalar times are finite in[-2^63,2^63). Native comparison includes fractional/negative/large finite times; invalid own-API times reject before state mutation without invoking invalid native calls.",
        "Native GenRender is used only to observe registry/frame metadata, with at most one live voice and alternating empty/nonempty frames; rebuilt synchronized audio is not compared here.",
        "Release-refresh is an observed hint. Rerelease transitions and subsequent synchronized voice modulation/audio remain separate integration work.",
        "Native factory/state/editor ABI, real host/project execution, cross-channel clock interactions and complete Fruity/VST/AU equivalence remain open.",
    ],
})
(here / "sync-lfo-verification.json").write_text(json.dumps(result, indent=2) + "\n")
