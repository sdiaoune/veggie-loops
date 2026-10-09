# Plugin reconstruction status

Full reconstruction is **incomplete**. No full FL Studio application or
complete installed plugin is certified. VL Studio’s audio engine includes an
optional VL 3 Osc instrument using the reconstructed raw core with its own
note envelope, preset and mixer.

Each row describes one bounded module. Later rows add separate proofs for
wrapper/state, voice integration, native adapters and context delivery; an
older row’s remaining work does not erase those later milestones. Complete
class/application/format/real-time equivalence remains unproved. The 146
family/format/application obligations are tracked separately from the 317
Mach-O binary corpus, which retains nested engines and runtime dependencies.

A source audit found retained-editor lifetime issues in four experimental
factories. Mute 2 and Phase Inverter now clear retained callbacks/context and
control targets, with two independent runtime reviews and a passing public
recipe. Soft Clipper and Stereo Shaper's own retained-view and storage repairs
passed two source runtime reviews and two engine runtime reviews; their current
public source includes the repairs, and the public package replay passes. Balance
has a separately accepted retained-view cleanup
repair. The three experimental oscillator factories now have a reviewed own
complete/caller-free versus deleting lifetime split. Center's repair passed two
source runtime reviews and two engine runtime reviews; its public working
replay passes. Fast Dist's first independent lifetime replay
failed an O0 editor allocation check and remains unaccepted while the failure
is traced. Other factories' complete
destructors remain under separate review.

| Component | Independently built and checked milestone | Remaining work |
| --- | --- | --- |
| Fruity Balance numerical core | Bitwise audio/parameter comparison, independently built C ABI, original-factory control/state/lifecycle comparison | Actual FL application loading and broader host integration |
| VL Balance experimental FL C++ interface | Intact FL engine loader accepts rebuilt module; 21 unchanged adapter methods and 20 callback slots; own AppKit controls/meters, host adapter callbacks and worker-thread regression checks | Full application/project/mixer and VL Studio integration; original VCL/artwork parity |
| [VL Balance public names/events and source lifetimes](effects/public-protocol/README.md) | 120 original/source name buffers, 36 events and 40 stored-field checks per mode; own complete/caller-free versus deleting cleanup, all three worker-refusal routes, loader/editor regressions and six wrong variants independently pass | Localization/all names, original extra destructors/class/allocator, original VCL, application/project/mixer, general FP/RT and whole-plugin equivalence |
| [VL Balance retained editor cleanup](effects/retained-editor/README.md) | All three lifetime routes, 144 instances, 72 attached worker refusals, 432 retained actions and live-peer callbacks per mode; three semantic negatives and two independent reviews, including direct editor/caller numerical ownership | Original editor/extra destructors/class/allocator, arbitrary reentrancy/concurrency, application hosting and whole-plugin equivalence |
| Fruity Mute 2 subset | Independent C ABI and experimental native factory; original-factory audio/state comparisons; intact engine loader, 20 callback slots, AppKit editor controls/automation, tick/thread/lifecycle checks | Original VCL/artwork parity, application/project/mixer and VL Studio integration |
| Balance and Mute 2 engine streams | Both modules save/restore through actual original memory/stream classes and engine plugin wrappers; signed32 HRESULT and count32 sentinel/error checks | Application-created project/preset serialization and mixer execution |
| Fruity Phase Inverter subset | Independent numerical core, experimental factory, intact engine loader/streams and own AppKit editor; native audio, state, tick, thread and lifecycle comparisons | Original VCL/artwork parity, full application/project/mixer and VL Studio integration |
| [VL Mute 2 / Phase Inverter source lifetimes](effects/mute-phase-lifetime/README.md) | 12 source profiles,10 semantic negatives and10 native outputs; complete retains raw storage,0/21 free; retained view targets/context clear; two runtime critics including borrowed-host supplement and public recipe pass | Original extra destructors/class/GUI/names/events, arbitrary concurrency, application/project/mixer, x86/VST/AU, RT and whole-plugin equivalence |
| Fruity Stereo Shaper subset | Source matrix/delay/phase processing, controls and state; experimental factory/intact engine loader, actual GetOutBuffer adapters/state streams, own AppKit editor and measured send registration; guarded allocation-failure checks | Original VCL, host cleanup ownership, full application/project/mixer and VL Studio integration |
| [Fruity Soft Clipper numerical subset](effects/SOFT_CLIPPER.md) | Two controls, exponential knee/gain, meters and valid state; 31,480 control cases and 3,422,287 frames, with independently repaired result/object aliasing | Broader control/UI/dispatch behavior, actual application/project/mixer and VST/AU integration |
| [Fruity Soft Clipper native bridge/editor](effects/SOFT_CLIPPER_NATIVE.md) | Own factory loaded by actual FLEngine DLL adapter; real state streams, 288 AppKit displays and repaired 256-case attachment/render locking independently replayed | Original VCL/resources, remaining dispatch/events/metadata, actual application/project/mixer, x86/VST/AU and whole-plugin equivalence |
| [Own Soft Clipper / Stereo Shaper lifetimes](effects/soft-stereo-lifetime/README.md) | Complete20 retains raw storage and0/21 free; retained views clear callbacks/context and control targets;12 normal/fatal/O0 source profiles,14 semantic negatives and18 actual-engine documents pass two separate pairs of runtime critics and the public package's52 signed arm64 products | Original extra destructors/class/GUI/allocator, actual application registration cleanup owner, broader provider/concurrency/RT and whole-plugin equivalence |
| [Fruity Center numerical subset](effects/CENTER.md) | Own centering filter/control/state C API; 1,516,707 exact stereo frames, live rate/reset/history and strict block-end flush checks; 342 sanitizer alias-rejection intervals independently replayed | Native class/streams/editor integration, complete dispatch/host lifecycle, x86/VST/AU and whole-plugin equivalence |
| [Fruity Center native bridge](effects/CENTER_NATIVE.md) | Own no-editor factory accepted by real FLEngine DLL loader; 20 callbacks, 140,700 frames and actual two-transfer streams with history-preserving read failures independently replayed | Original Pascal/VCL, full destructor/general-provider ABI, remaining metadata/dispatch, actual application/project/mixer, x86/VST/AU and whole-plugin equivalence |
| [VL Center optional AppKit editor](effects/CENTER_EDITOR.md) | Real host/plugin adapters, preserved filter displays, four maintained checks and independent enabled-history/ThreadSanitizer replay; refused worker destruction retains ownership | Original GUI/hints/resources, full application/project/mixer and destructor/provider semantics, x86/VST/AU, general concurrency/RT and whole-plugin equivalence |
| [Own Center factory lifetimes](effects/center-lifetime/README.md) | Complete20 retains raw storage and0/21 free; retained views clear callbacks/context and control targets;9 normal/fatal/O0 source profiles,4 semantic negatives and10 actual-engine documents pass two runtime critics and the public working package's29 signed arm64 products;15 fake-only publication failure controls pass | Original extra destructors/class/GUI/allocator, application scheduling, broader provider/concurrency/RT and whole-plugin equivalence |
| [Fruity Fast Dist numerical subset](effects/FAST_DIST.md) | Independently regenerated 163,880 table entries, both host DSP branches and five controls; actual factory/initialized host, sanitizer and 1,075,200 additional edge-float comparisons; wrong quality branch fails | Actual host quality production, original class/GUI/host semantics, broader state-provider errors, x86/VST/AU and whole-plugin equivalence |
| [VL Fast Dist native bridge](effects/FAST_DIST_NATIVE.md) | Actual DLL loader accepts own fixed-quality0 factory; 20 callbacks, 140,700 frames and 128 real-stream roundtrips; two critics and signed-HRESULT/count negative control | Original Pascal/VCL/editor, quality configuration, remaining metadata/dispatch, general provider/extra destructors, actual application/project/mixer, x86/VST/AU and whole-plugin equivalence |
| [VL Fast Dist optional AppKit editor](effects/FAST_DIST_EDITOR.md) | Four maintained checks through real adapters/loader/streams; main hint locking, 128 enabled attachment cycles, independent 256 interpolated cycles/20 malformed states/ThreadSanitizer and missing-lock negative; own readable controls | Original host quality production, original GUI/hint/resources, full application/project/mixer and remaining ABI/provider/destructor behavior, x86/VST/AU, general RT and whole-plugin equivalence |
| [Prepared original process-mode delivery](effects/quality-provider/QUALITY_PROVIDER.md) | Intact original provider/receiver and both separately supplied DistWave selectors; four fatal/normal replay checks, signed packet/retain/guard checks and independent mode-to-quality negative | Source provider reconstruction, genuine selector writers/quality UI binding, real lock/class/host ownership, whole state/application/FP/RT and plugin equivalence |
| [VL Fast Dist supplied-host factory](effects/host-delegated/HOST_DELEGATED.md) | Own five-control/coefficient/state implementation delegates audio to borrowed host ordinal24; real adapters/intact loader, 7,200 renders and 128 actual-stream roundtrips pass normal/fatal replay; maintained manual-adapter and separate reviewer loader-adapter negatives | Independent host/DSP in this runtime, genuine selector production/application ownership, original GUI/class/metadata, broader ABI/provider/FP/RT, VST/AU and whole-plugin equivalence |
| 3x Osc small DSP engine | All 45 public exports; generated wavetables/mipmaps, FFT, public class ABI, custom waves, rendering and serial multi-instance lifecycle checks | Full Fruity wrapper, polyphony, modulation, editor and application hosting |
| 3x Osc wrapper subset | 114 control slots, version-14 state field storage, HQ/legacy raw voice rendering and multi-voice lifecycle; bounded original-factory comparisons; raw core integrated into the VL 3 Osc instrument | Integrated-editor envelopes/filter/modulation, original final mixing, native factory ABI, GUI and full application hosting |
| 3x Osc isolated envelope and legacy banks | Prepared envelope/LFO transitions, tempo/clock coefficient math and six procedural legacy waveform banks independently compiled and compared exactly | Host tick input production, voice-pipeline integration, filters/final mixer and native factory/GUI |
| 3x Osc prepared modulation and filters | Five envelope/LFO groups: 15,940,800 exact state/pitch values; filter coefficient/kernels: 46,446,912 exact audio/state values across seven rate contexts | Actual clock/context production, activation/routing, full voice audio integration and native factory/GUI |
| 3x Osc prepared filter routing | 1,200 synthetic contexts, 14,400 calls and 16,747,200 exact audio/state/gain values; bypass, activation, slew, one/two-pass processing and gain compensation | Runtime mode/rate changes, native factory/editor/host routing and full voice integration |
| 3x Osc default voice and output math | HQ/legacy default voice pipeline: 180 original factories, 2,160 render blocks and 2,046,600 exact floats; separate gain mixing and 441-sample release table comparisons | Enabling and routing envelope modulation/filter features, pitch automation, wider pitch domain, native factory and GUI |
| [3x Osc prepared active voice](generators/PREPARED_VOICE.md) | Five-group modulation, fixed type0 filter, release and final gains; 360 original factories, 8,640 render calls, 8,186,400 exact audio floats and 1,486,080 state values | Actual host PPQ/tick production, synchronized LFOs, live mode/context changes, native factory, editor and full hosting |
| [3x Osc voice lifecycle metadata](generators/VOICE_LIFECYCLE.md) | 7,200 original triggers, 3,775 quick-release selections, 3,261 ordered completion requests and 1,554,240 exact metadata values | Active-envelope release transitions, complete voice objects/audio integration, allocation behavior and actual host scheduling |
| [3x Osc active channel](generators/CHANNEL.md) | Source-owned core/voices, active-envelope ordinary/quick release, soft polyphony and ordered notifications; 6,480 native triggers, 20,806,805 exact state values and 4,093,200 overwritten host-output floats | Actual host PPQ/tick delivery, synchronized LFOs, runtime mode/context changes, native factory/state/editor and full application hosting |
| [3x Osc synchronized LFO metadata](generators/SYNC_LFO.md) | 360 native factories, 30,960 controlled public seeks and 4,056,342 exact metadata values; signed64/mod32 boundaries independently checked | Actual clock delivery/scheduling, live contexts, native allocating/concurrent list ABI and full factory/editor/host |
| [3x Osc synchronized channel](generators/SYNCHRONIZED_CHANNEL.md) | Live flag registration and volume-release refresh; 24,811,720 exact voice-state values and 4,093,200 overwritten audio floats independently replayed under sanitizers; omitted-refresh negative control fails | Supplied fixed contexts/type0, other modes, native factory/state/editor, actual application clock/host and whole-plugin equivalence |
| [3x Osc channel with eight filter modes](generators/MULTIMODE_CHANNEL.md) | 810 triggers per public mode, 522,352 captured-mode values and 3,960 heterogeneous renders; exact state/audio replay and sanitizers pass; wrong live-mode override fails independent negative control | Supplied fixed contexts, other oscillator/kernel modes, native factory/state/editor, actual clock/project/host and whole-plugin equivalence |
| [VL 3 Osc bounded C++ factory](generators/NATIVE_FACTORY.md) | Actual engine loader/adapters, 114 controls and valid state; 180 original/source factory comparisons, 6,480 triggers and 4,093,200 audio floats pass normal/sanitized replay; wrong release/kill slots fail | Original Pascal class/editor, actual clock/table production and scheduler ownership, live contexts, unsupported callbacks, broader state/provider and whole-plugin equivalence |
| [Prepared engine clock context](generators/CLOCK_CONTEXT.md) | Intact tick provider/direct descriptor producers and real C++ adapters; exact packets, repaired FRINTX inexact status, fatal sanitizers, independent edge/negative and required-two-run checks | Live clock production, queued/project/voice delivery, application-owned manager/host/sender, actual rate producer, general FP/trap/RT and whole-plugin equivalence |
| [Prevoice context delivery](generators/CONTEXT_DELIVERY.md) | Unchanged source factory receives rate/PPQ/tempo through real descriptor/adapters before first voice; 72 fixtures, 225,072 overwritten audio floats, two fatal/normal replays and independent fail-closed checks | Actual application clock/rate producer and host ownership, queued/live context delivery, general FP/RT and whole-plugin equivalence |
| [3x Osc active context and preparation cache](generators/live-context/IMMEDIATE_PREPARATION.md) | Source retains voices while refreshing measured active configuration caches; 96 next-use pairs, 16 timing pairs, 240 immediate masks and 44,400 prepared words match; normal/fatal/O0 builds, old-lazy timing negatives and required-result guards independently pass | Immediate prevoice preparation, other active controls/state/sync/release/seek, original class/editor, actual clocks/host ownership, general FP/RT, VST/AU and whole-plugin equivalence |
| [3x Osc preparation before the first voice](generators/prevoice-preparation/README.md) | Five eager caches, zero-curve/restore history and first-voice handoff; two independent preparation reviews and two separate lifetime reviews; public normal/fatal/O0 replay matches18 documents and rejects five numerical variants and five incomplete summaries | Fresh audio without rate delivery, arbitrary active controls/state/synchronization, original class/GUI, application clock production, VST/AU, general FP/RT and whole-plugin equivalence |
| [Own 3x Osc factory lifetimes](generators/lifetime/README.md) | Stock/immediate/prevoice complete20 retains raw storage and0/21 free; nine source profiles,12 fatal semantic negatives and27,648 same-source peer floats; two independent runtime critics and public recipe pass; maintained stock/live regression documents remain exact | Original extra destructors/class/GUI/general allocator, application hosting, VST/AU, real-time and whole-plugin equivalence |
| [LABS caller-managed meter source contract](external/labs/meter/README.md) | Own unfused meter/table API; unchanged C++ and synthetic test controls accepted by author and two independent source runtime critics; standalone package passed two static reviews,23 fake-only failure controls and public working/fresh3-profile/9-negative replays with12 strictly signed arm64 products each | Original instruction/ABI/FMA/fenv/global/allocator/class parity, synthesis/sample audio, VST/AU, RT and whole-plugin reconstruction |
| Vital upstream source | Optional GPL Vial 1.0.6 build recipe: fresh public source builds arm64 VST3/AU and an experimental SDK-free legacy wrapper; native MIDI/audio and semantic state checks; narrow deterministic comparison with installed Intel Vital 1.0.7 | Version gap, editor/automation/playhead/RT and broader preset/layout/rate checks; valid-state-only legacy loader; disclosed sample-state fix changes original behavior |
| [TyrellN6 parameter conversion subset](external/tyrell/PARAMETER_SCALE.md) | 92 actual descriptors, 920 unmodified-manager round trips and 188,784 native callback comparisons; independent non-grid/FMA/signed-zero and sanitizer checks | Parameter manager, voice/audio/DSP, presets/state, GUI, automation, rebuilt VST/AU factories and full hosting |
| [TyrellN6 prepared parameter manager](external/tyrell/PARAMETER_MANAGER.md) | 92 real descriptor types/maps, 254,472 native setter decisions and 477 atomic rejects; two independent reviews, nongrid/zero/type/state probes and wrong-rounding negative control | Substituted downstream getter/notifier, real audio target/scheduling, native manager/factory ABI, presets/state, GUI, RT and full DSP/plugin |
| [TyrellN6 actual raw storage getter](external/tyrell/DOWNSTREAM_GETTER.md) | All 213 internal/92 public IDs, four storage routes and exact float payloads; corrected fatal sanitizer fixtures, two independent critics and deliberate alignment-error rejection | Real notifier/range/queue/DSP scheduling, integration into prepared manager, native class/factory/state/GUI, FP exception flags, RT and whole-plugin equivalence |
| [TyrellN6 prepared notifier storage](external/tyrell/NOTIFIER_STORAGE.md) | Actual unchanged notifier/allocated queue, strict range/rounding/motion/cyclic decisions; fatal sanitizer and independent native edges/atomic checks/queued-gain negative; 55 outside-change observations explicitly excluded | Unit callback effects, native class/factory and whole-state ownership, live queue production/consumption, audio/presets/GUI/VST/AU, RT and whole-plugin equivalence |
| [TyrellN6 prepared no-XY queue consumer](external/tyrell/QUEUE_CONSUMER.md) | Actual unchanged callback, 17,290 captured/restored direct calls, 6,609 ordinary original renders and 118 completions; independently built scalar queue progression/revisit/reverse-copy API, fatal two-architecture contracts and four negative controls | Nonvisited-word effects (6,614 initially; 6,618 in a fresh checkout), active XY and unit effects, source audio/DSP, scheduler/class/factory/state/GUI, general FP/RT and whole-plugin equivalence |
| [TyrellN6 prepared XY consumer](external/tyrell/prepared-xy/README.md) | Independently written empty-queue scalar consumer; integer-only unused-field validation and coordinate evaluation order; normal/fatal/O0, ten wrong variants and two copied independent reviews, including shared cells and actual inherited FP environments | Natural active XY and positive queues, source audio/DSP, native class/factory/state ownership, scheduler/editor/RT and whole-plugin equivalence |
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

LABS now has nonempty local REA output for all 26,396 identified internal
non-thunk arm64 VST2 procedures across two disclosed analysis profiles. Its
default 50MiB decompiler limit failed for one procedure, including a repeat
check. A separate copied bridge with a 256MiB limit and a distinct profile
commitment supplied that complementary result. Original failures and outputs
are preserved; all compressed/raw and semantic evidence hashes were checked.
That corpus is decompiler analysis. A separate caller-managed meter module now
has an independently built own-source contract; its supported storage API and
synthetic tables do not establish original LABS numerical, class, audio or
VST/AU equivalence.

TyrellN6's 8,448 identified internal non-thunk x86_64 VST procedures also have
local REA decompiler results. Some recovered call signatures and indirect
dispatch targets remain uncertain. The installed factory and callback mapping
are reference observations. A bounded independently built parameter range/
conversion subset passed original-callback comparisons. Its sound engine,
state, GUI and complete native source build remain unfinished.

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
