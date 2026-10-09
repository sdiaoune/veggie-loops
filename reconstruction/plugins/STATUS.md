# Plugin reconstruction status

Full reconstruction is **incomplete**. No full FL Studio application or
complete installed plugin is certified. The workstation's original audio
engine now includes an optional VL 3 Osc instrument using the reconstructed
raw core with its own note envelope, preset and mixer.

| Component | Independently built and checked milestone | Remaining work |
| --- | --- | --- |
| Fruity Balance numerical core | Bitwise audio/parameter comparison, independently built C ABI, original-factory control/state/lifecycle comparison | Actual FL application loading and broader host integration |
| VL Balance experimental FL C++ interface | Intact FL engine loader accepts rebuilt module; 21 unchanged adapter methods and 20 callback slots; original AppKit controls/meters, host adapter callbacks and worker-thread regression checks | Full application/project/mixer and VL Studio integration; original VCL/artwork parity |
| Fruity Mute 2 subset | Independent C ABI and experimental native factory; original-factory audio/state comparisons; intact engine loader, 20 callback slots, AppKit editor controls/automation, tick/thread/lifecycle checks | Original VCL/artwork parity, application/project/mixer and VL Studio integration |
| Balance and Mute 2 engine streams | Both modules save/restore through actual original memory/stream classes and engine plugin wrappers; signed32 HRESULT and count32 sentinel/error checks | Application-created project/preset serialization and mixer execution |
| Fruity Phase Inverter subset | Independent numerical core, experimental factory, intact engine loader/streams and original AppKit editor; native audio, state, tick, thread and lifecycle comparisons | Original VCL/artwork parity, full application/project/mixer and VL Studio integration |
| Fruity Stereo Shaper subset | Source matrix/delay/phase processing, controls and state; experimental factory/intact engine loader, actual GetOutBuffer adapters/state streams, own AppKit editor and measured send registration; guarded allocation-failure checks | Original VCL, host cleanup ownership, full application/project/mixer and VL Studio integration |
| 3x Osc small DSP engine | All 45 public exports; generated wavetables/mipmaps, FFT, public class ABI, custom waves, rendering and serial multi-instance lifecycle checks | Full Fruity wrapper, polyphony, modulation, editor and application hosting |
| 3x Osc wrapper subset | 114 control slots, version-14 state field storage, HQ/legacy raw voice rendering and multi-voice lifecycle; bounded original-factory comparisons; raw core integrated into the VL 3 Osc instrument | Integrated-editor envelopes/filter/modulation, original final mixing, native factory ABI, GUI and full application hosting |
| 3x Osc isolated envelope and legacy banks | Prepared envelope/LFO transitions, tempo/clock coefficient math and six procedural legacy waveform banks independently compiled and compared exactly | Host tick input production, voice-pipeline integration, filters/final mixer and native factory/GUI |
| 3x Osc prepared modulation and filters | Five envelope/LFO groups: 15,940,800 exact state/pitch values; filter coefficient/kernels: 46,446,912 exact audio/state values across seven rate contexts | Actual clock/context production, activation/routing, full voice audio integration and native factory/GUI |
| 3x Osc prepared filter routing | 1,200 synthetic contexts, 14,400 calls and 16,747,200 exact audio/state/gain values; bypass, activation, slew, one/two-pass processing and gain compensation | Runtime mode/rate changes, native factory/editor/host routing and full voice integration |
| 3x Osc default voice and output math | HQ/legacy default voice pipeline: 180 original factories, 2,160 render blocks and 2,046,600 exact floats; separate gain mixing and 441-sample release table comparisons | Enabling and routing envelope modulation/filter features, pitch automation, wider pitch domain, native factory and GUI |
| [3x Osc prepared active voice](generators/PREPARED_VOICE.md) | Five-group modulation, fixed type0 filter, release and final gains; 360 original factories, 8,640 render calls, 8,186,400 exact audio floats and 1,486,080 state values | Actual host PPQ/tick production, synchronized LFOs, live mode/context changes, native factory, editor and full hosting |
| [3x Osc voice lifecycle metadata](generators/VOICE_LIFECYCLE.md) | 7,200 original triggers, 3,775 quick-release selections, 3,261 ordered completion requests and 1,554,240 exact metadata values | Active-envelope release transitions, complete voice objects/audio integration, allocation behavior and actual host scheduling |
| Vital upstream source | Optional GPL Vial 1.0.6 build recipe: fresh public source builds arm64 VST3/AU and an experimental SDK-free legacy wrapper; native MIDI/audio and semantic state checks; narrow deterministic comparison with installed Intel Vital 1.0.7 | Version gap, editor/automation/playhead/RT and broader preset/layout/rate checks; valid-state-only legacy loader; disclosed sample-state fix changes original behavior |
| Other installed plugins | Identity, architectures, dependencies and factory inventory; further native analysis underway | Independent source reconstruction, native builds, processing/state/UI tests and critique |
| Purity envelope curve | Independently generated 259-float curve; 532,245 values across 2,055 amounts compared exactly, with guarded output and new-ABI invalid rejection | Native class ABI, voice/audio pipeline, state, MIDI, factory, editor and hosting |
| Purity ADSR follower | 970,888 exact prepared state records; repeated steep-curve/one-sample and immediate note-off overshoot regressions fixed and independently replayed | Caller scheduling/level accumulation, full voice pipeline, native factory, editor and hosting |
| Purity prepared peak/RMS compressor routines | Each source routine matched 14,112 retained-state cases and 5,625,216 stereo frames; bounds, guards, overlap and rejection behavior independently reviewed | Complete effect-chain/wet-dry preparation, voice chain, factory, state, UI and hosting |
| [Purity live compressor classes](external/purity/classes/README.md) | Real source Peak64/RMS72 C++ objects and sixteen virtual slots; 864 original factory creations, 5,512,320 frames, 31,104 displays and 18 allocation failures independently replayed under sanitizers | Full effect-chain/wet-dry routing, native VST/AU factory identity, plugin state, editor, MIDI, realtime and application hosting |

The standard-path external inventory contains 12 top-level bundles: five VST2,
two VST3 and five AU. These represent FL Studio wrappers, LABS, Purity, Vital
and TyrellN6. The bundled native inventories contain 84 effect families and
49 generator folders. Counts include wrappers and shared engines and must not
be interpreted as independent reconstructed products.

The installed FL AU wrapper's 194 identified internal non-thunk procedures now
have local REA decompiler results. This is analysis coverage, not source builds
or whole-wrapper equivalence. The installed Purity, Vital and TyrellN6 VST2
originals also passed a disclosed nine-case rate/block audio reference matrix.
LABS default reference audio remains silent; no third-party plugin has been
certified as fully reconstructed.

Purity's 4,459 identified internal non-thunk arm64 VST procedures now have
local REA decompiler results. Its separately compiled envelope curve is one
mathematical primitive. The optional Vial source build also passed a 56-case
processing/state matrix using generated state without loading installed Vital.
Both remain partial milestones, with whole-plugin completion false.

TyrellN6's 8,448 identified internal non-thunk x86_64 VST procedures also have
local REA decompiler results. Some recovered call signatures and indirect
dispatch targets remain uncertain. The installed factory and callback mapping
are reference observations; an independent TyrellN6 source build is unfinished.

The successful cases are finite disclosed test domains. Matching export names
or compiling all identified functions does not prove arbitrary input, exception
unwinding, resource, GUI or whole-plugin equivalence. Source and native binary
hashes bind the local evidence to the inspected installation.

Use the [effects](effects/README.md), [generator](generators/README.md) and
[native host](common/README.md) instructions to reproduce their respective
checks. Original reconstruction code is published; target binaries, machine
code slices, commercial assets, decompiler outputs and captured states remain
local. The optional [Vial module](external/vial/README.md) is explicitly
GPL-3.0-or-later; its external upstream source and SDK dependencies retain
their own licenses and are fetched separately.

The [ownership and acceptance plan](../../docs/PLUGIN_RECONSTRUCTION_PLAN.md)
defines the implementation → independent critique → repair → verification loop.
