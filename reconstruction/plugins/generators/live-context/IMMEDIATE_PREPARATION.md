# Bounded active context preparation

This independently written channel/factory variant passed root and two independent critic reviews against the identified macOS arm64 originals. It prepares and stores actual envelope/LFO coefficients at the measured active calls. It does not establish complete 3x Osc or FL Studio reconstruction. Shared numerical helpers remain unchanged.

The original active event 0 stores the delivered float tempo and prepares all five 160-byte groups, even for repeated tempo. Listed raw group-control writes prepare their group; the same valid active state restore prepares all groups. Dispatcher 14 stores PPQ without recomputing these coefficients. Rate dispatcher 4 changes the raw scaler/filter rate while retaining voices, borrowed parameters, handles, phase, gains and history. The source caches the actual configurations and uses them on subsequent ticks, renders, release and triggers; current synchronized phase is supplied separately. A zero curve preserves the previously prepared inverse/log fields.

The distinct `veggie_loops::three_osc::immediate` helper uses `rint` for the observed native FRINTX operation. It does not raise exception flags artificially or override the immutable shared helper definitions. A source library built at O0 passes the same three result documents as O2.

This variant's no-voice route retains its existing lazy delivery behavior. The separate [prevoice preparation module](../prevoice-preparation/README.md) covers measured preparation before the first voice. The measured extension here starts after a channel and active voice exist; the explicit prepared helper still refuses active changes. The factory retains its bounded metadata/name stubs and controlled callback/table contract. Names require 256 writable bytes. Calls across all raw-engine/factory instances are serialized, with no reentrant mutation; callbacks are synchronous, nonthrowing and defer voice deletion. Borrowed 40-byte parameters and tables must remain live.

Run on macOS arm64 with the exact identified installed FL Studio binaries and Apple's compiler:

```sh
sh reconstruction/plugins/generators/live-context/verify_immediate_context.sh
sh reconstruction/plugins/generators/live-context/verify_immediate_context.sh --sanitize
sh reconstruction/plugins/generators/live-context/verify_immediate_O0.sh
python3 reconstruction/plugins/generators/live-context/summary_negative_probe.py
python3 reconstruction/plugins/generators/live-context/summarize_immediate_context.py
```

Run these commands sequentially. O0 uses the required canonical-native harnesses; the summary requires both canonical modes, O0, old-lazy negatives and summary-rejection results. Outputs stay under ignored `.tools/plugin-work/generators/live-context-public/`. `VL_IMMEDIATE_CONTEXT_PROJECT_ROOT` selects a mirrored source root for compiler scripts. The public summarizer accepts an optional project root and work base. It pins all ten compiled current/baseline files, the unchanged 24-file public dependency closure and four native identities before writing a verification manifest. Missing, failed, diagnostic or mismatched evidence rejects publication of a success manifest.

The canonical tests cover three separate finite domains:

- Prevoice numerical regression: 72 fixtures, 144 intact TExPlugin direct-Pascal/actual-CPP routes, 288 balanced controlled retains, 13,320 coefficient words, 61,560 voice values and 225,072 overwritten audio floats. This does not measure immediate prevoice preparation parity or execute the original rate producer.
- Live next-use regression: 96 fresh pairs and six disclosed transitions across eight fixed filter modes and correlated legacy/HQ flags. 672 snapshots / 63,840 state values and 114,816 audio floats match. The initial context is44,100 Hz/120 BPM/PPQ 240; transitions include repeated context,96,000 Hz,60 BPM, PPQ 960 alone, PPQ 960 with120 BPM and22,050 Hz/PPQ 48/137.125 BPM.
- Active timing/cache regression: 16 fixed pairs, 240 immediate masks and 44,400 defined configuration words match with complete caller fenv restore/readback. Listed calls include repeated/changed tempo, PPQ-only, rate changes, group 0 attack 4000/5000/repetition, curve 16/0/16 and the same valid active 460-byte state restore. PPQ-only masks are 0/0; the other listed masks are FE_INEXACT 16/16. Sixteen second voices after PPQ-only delivery, 288 repeated context operations, 192 renders / 20,352 audio floats and 304 source-only context rejections also pass.

Configuration comparisons exclude target-specific table pointers and runtime synchronized phase; voice/filter/borrowed-parameter snapshots are compared separately. Selected wrapper spans and the prevoice fixture's selected engine spans are restored/read back after nominal destruction. This is not restoration of every native global, TLS, object, table, module or GUI state. Sanitizers instrument the reconstructed sources and fixtures; installed images remain uninstrumented.

The three `lazy-baseline/` files are byte-identical retained source support for a **separately compiled negative**, not an accepted complete plugin. Their old lazy preparation fails the first same-tempo check with native 16/source 0 in both normal and fatal-sanitizer builds. No original machine code or commercial assets are included in this directory.

The immediate factory includes the separately reviewed [own lifetime repair](../lifetime/README.md).
Complete callback20 ends the instance and retains raw storage for caller release;
callbacks0/21 end and free it. Its first twenty table expressions and non-lifetime
callback bodies are unchanged. Normal, fatal and O0 maintained regression documents
still match the accepted scalars. Original extra-destructor/class semantics remain
unproved. Signed arm64 products are strictly verified before use; O0 borrows the
already signed canonical-native harnesses from the preceding normal run.

The verification metadata retains frozen hashes of ignored private maps, failures and review reports as provenance references. The public recipe does not read those files or reproduce those historical experiments. Independent critic extensions are recorded separately: 10,840 native helper/rounding/fenv cases and an all-five-group guarded refresh/two-voice extension; another critic measured 19,456 inherited sticky masks / 3,599,360 prepared words and 1,328 source-only preservation rejections. These are not added to canonical counts.

Prepared scalar domains and raw control bounds remain those in the source headers. The successful active corpus is narrower: nontrapping nearest-even arithmetic with gradual underflow, listed controls/restore and fixed mode/flag pairs. General fenv/errno/traps, other rounding/flush modes, arbitrary active or normalized controls/state, synchronized flag 32, release/seek/live-mode and cross-instance timing are unproved. Actual application clock/rate producers, host/table ownership, scheduling/concurrency/real-time behavior, original Pascal class/editor/metadata, VST/AU and whole-plugin equivalence remain false. Final public-path review and Git publication belong to root.
