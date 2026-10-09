# Bounded 3x Osc channel with public filter modes

This separate original channel extends the synchronized voice pipeline to all eight exposed filter modes, including mixed channels whose voices were created under different modes. It supplies a new C API and uses the published raw core, synchronized metadata and DSP primitives without changing their APIs. Native Fruity/VST/AU factories, full state/editor ABI and actual host scheduling remain unfinished.

Run `./reconstruction/plugins/generators/multimode-verify.sh` for the native differential comparison, or add `--sanitize` to instrument the rebuilt dylib and fixture with AddressSanitizer, UndefinedBehaviorSanitizer and float-cast-overflow checks. Each mode uses a separate private output directory. The source/target/artifact bindings and native/sanitized results are recorded in `multimode-verification.json`. Original target/dependency hashes and a macOS arm64 guard protect every fixed-offset call and data read. The rebuilt module links independently written source and Apple Accelerate, with no captured commercial code, assets or tables.

Public filter-mode parameter 113 defaults to 0. The native constructor at arm64 `1bc8d0` reads configuration `+0x330` and captures the two table bytes at `262fb0`/`262fb1` into each new voice. Mode changes affect later notes; an existing voice keeps its filter type, order and carried history representation. The internal dirty latch at configuration `+0x334` controls synchronized LFO registration separately.

| Public mode | Kernel type | Double order |
|---|---:|---:|
| 0 | 0 | 0 |
| 1 | 1 | 0 |
| 2 | 2 | 0 |
| 3 | 3 | 0 |
| 4 | 4 | 0 |
| 5 | 1 | 1 |
| 6 | 6 | 0 |
| 7 | 6 | 1 |

Type 0 begins inactive and latches active when cutoff/resonance requires filtering. Positive types begin active. Histories start zero, matching `6dbe0`, then remain in their original per-voice representation. The `1bcd60` routing prepares coefficients, runs one or two passes, applies the biquad double-order gain compensation and adjusts/resets resonance for the special second pass. Types 5/7, table entries beyond public mode 7 and changing an existing voice's history type are outside this public-mode integration.

The corpus uses 180 actual original factories paired with reconstructed channels. Each fixture performs 24 rounds with one or two note triggers, ordinary/repeated/quick releases, changing soft limits and rendering lengths 1/2/3/7/8/9/15/16/63/441/1024/4096. Mode 113 changes before later triggers while existing voices remain alive. The fixture reads and checks all 16 native mapping bytes, records triggers per public mode, verifies each voice retains its captured mapping after subsequent control changes, and counts frames containing different captured modes.

Raw waveforms 0..4, HQ/legacy, group flags 0..63, all three LFO shapes, curves and depths vary. Inversion/ring/random-phase controls remain at defaults. Rate/tempo pairs 44100/60, 48000/90, 96000/120, 22050/137, 8000/240 and 384000/1000 each cross explicit PPQs 4/48/96/240/960/4096. These contexts remain fixed per fixture. Dispatcher 14 `FPD_SetTimeSig` receives PPQ at Value `+8`; the caller supplies ticks and controlled 16-byte `FHD_GetMixingTime`/`GT_Ticks` pairs. Live group registration and volume-enabled changes include the volume-stage 6 release-refresh transition. Actual application time delivery and scheduling are not reconstructed.

Every mutation compares synchronized context metadata and each live voice's 45 modulation words, 112 filter bytes, two gains, release fields, six raw phases, stereo flag and 40 borrowed parameter bytes. Final pan/volume, restored base pitch [−2400,2400] and ModX/ModY [−.25,.25] vary per block. Audio matches every float exactly when overwriting varying nonzero host samples; nonzero leading/trailing guards survive. Filter history measurements read type 0 histories as doubles and positive-type histories as floats. Only finite observed histories, working samples, gains and output are counted; their maxima are recorded. This finite carried-state comparison extends smaller isolated kernel domains without arbitrary-history/amplitude equivalence.

Completion callbacks match `VoiceKill(tag,-1)` in voice order. They are controlled, nonthrowing and defer all mutations until render returns. Completed voices sometimes remain for a second notification, then explicit kill removes them. New API RAII teardown with voices still owned is compared after explicit native voice cleanup, so identical original destruction ownership is not claimed. Tables and borrowed parameters outlive their voices/channel, output storage does not overlap them or state/callback context, and the caller serializes every raw-engine instance sharing global factory/RNG state.

The API admits rates [8000,384000], tempo (0,1000], PPQ [4,2^20], finite [−1,1] tables with 16384 samples, filter depths [−32,32], base levels within the header's bounds and finite tick positions [−2^63,2^63). This is broader than the six paired rate/tempo settings replayed here. Strict float flags, nearest-even rounding and gradual underflow are required. Invalid new-API times/frames/current modes/pitches preserve compared state, output and notifications; those invalid calls are not sent to the original. Injected allocation failures, reentrant callbacks and alternative float environments are unproved.

Remaining gates include oscillator/custom/noise modes, live rate/tempo/PPQ delivery, cross-channel contexts, actual host callbacks/clock/project execution, native object/factory/state/editor ABI and complete Fruity/VST/AU equivalence. The new channel does not supply a full-plugin certificate.
