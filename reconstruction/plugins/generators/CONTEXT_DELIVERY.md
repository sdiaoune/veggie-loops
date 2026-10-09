# Prevoice context delivery

This fixture compares prepared sample-rate, PPQ and tempo delivery before the
first voice. It uses the unchanged reviewed source factory/channel and makes
no manual `vl_private_osc_prepare` call. The source channel remains null through
creation, parameter/state storage and descriptor delivery; the first
`TriggerVoice` creates it. The fixture is byte-identical to the independently
reviewed private prevoice test. Root independently replayed the public recipe and summarizer in a source-only
copy, with normal and fatal sanitizer results and five rejection controls.

Intact engine entry 0x32e000 sends dispatcher 14 then 20; entry 0x32e1f0 sends
event 0 then 20. Original object resolution and refcount machinery execute with
controlled manager retain/release/get callbacks. The original target is an
actual unchanged Pascal factory. The source target is the intact engine's
C++ plugin adapter around the compiled source factory. Its actual C++ host
adapter wraps controlled Pascal host methods for paths, stereo gains and
nondeleting notifications. These routes and substitutions remain distinct.

Dispatcher 4 receives a prepared integer sample rate directly at each measured
target entry. The whole native DLL loader and its rate producer are not
executed. Dispatcher 14 reads the PPQ word at Value+8; event 0 reads float tempo
bits. Dispatcher 20 and event flags do not alter the compared output. Selected
engine/wrapper globals are snapshotted and restored after every instance is
destroyed. This covers selected spans, not complete process or class state.

The canonical corpus has 72 fixtures: 36 contexts with two different supplied
samples-per-tick metadata values. Six correlated sample-rate/tempo pairs are
8000/60,22050/90,44100/120,48000/137.125,96000/240 and 384000/1000, each with
PPQ 4,48,96,240,960 or 4096. Signature words remain 16/4. Comparison clocks include
1.5,2.5,183.75,16777217,4294967295.5 and 2^32. The canonical clock formula is a
prepared fixture value, not measured application clock production. Flags 0..31
exclude synchronized flag 32. Filter modes 0..7 remain fixed per instance;
HQ/legacy deterministic oscillators 0..2, static pitches [-900,900] cents and
bounded envelope/filter controls are covered. Noise, random phase, custom
waves, synchronized context and live context/mode changes are excluded.

The required result checks 144 routes,288 balanced retains,360 native context
values,13,320 coefficient words,32,904 semantic preset bytes,61,560 voice
state values and 225,072 overwritten audio floats over 576 render calls.
Coefficient pointer words and synchronized phases are excluded. Preset bytes
93..95 are undefined native padding and excluded. The native wrapper's own
internal LFO table contents compare with independently generated tables;
separate raw oscillator tables are supplied by the controlled host. Every
note keeps 40 borrowed parameter bytes alive until explicit `KillVoice`.
Nonzero buffer guards, notices, state, frame lengths and output bits compare.
Calls are serial with valid addresses/tables, nearest-even rounding, gradual
underflow, separate operations and nonthrowing callbacks that defer deletion.

Run from the project root:

```sh
sh reconstruction/plugins/generators/verify-context-delivery.sh
sh reconstruction/plugins/generators/verify-context-delivery.sh --sanitize
python3 reconstruction/plugins/generators/summarize_context_delivery.py
```

Outputs use the separate ignored directory
`.tools/plugin-work/generators/context-delivery-public/canonical-{native,sanitized}`.
The script retains source/output overrides for isolated copies; the summarizer
uses these default output locations in the selected project root. Both normal
and fatal ASan/UBSan/float-cast-overflow runs are required. Missing outputs,
failed results or sanitizer diagnostics reject before a success manifest is
written. The summarizer checks the reviewed fixture, all 26 dependency hashes
and four installed target identities. Only new source/fixtures are instrumented;
the installed originals remain unmodified and uninstrumented.

A fresh checkout needs those public sources, both generated replay outputs
and the pinned installed originals. Ignored private mapping, failure, negative
and review files are preserved as hash references in the manifest; the recipe
does not read, require or reproduce their data. The private PPQ-omission and
critic tempo-omission mutants failed voice-state comparisons. Private summary
absence/failure checks also rejected. A first disk-exhausted sanitizer build
and a rejected host/internal-LFO pointer assumption remain separate evidence.

Root and mixer reviewers accepted the bounded private fixture. The critic's
additional 72-fixture corpus uses 36 independent rate×tempo pairs and alternating
signature words 1/1024, with an explicitly prepared clock clamp. That extension
is separately referenced and is not run or counted by this canonical recipe.
The critic's first run used the wrong directory; its separate disclosure is
excluded from isolated proof. Subsequent copied replays passed with unchanged
author bindings.

Application clock/host ownership, whole DLL rate production, queued delivery,
active-voice context changes, real scheduling, complete Pascal factory/class
metadata, original GUI, invalid native inputs/allocation failure, floating
status/traps, real-time guarantees and full-plugin equivalence remain unproved.
No original machine code, assets or presets are included.
