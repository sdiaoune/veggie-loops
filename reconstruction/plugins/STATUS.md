# Plugin reconstruction status

Full reconstruction is **incomplete**. No full FL Studio application or
complete installed plugin is certified. The workstation's existing native
audio engine and instruments remain its original implementation.

| Component | Independently built and checked milestone | Remaining work |
| --- | --- | --- |
| Fruity Balance numerical core | Bitwise audio/parameter comparison, independently built C ABI, original-factory control/state/lifecycle comparison | Actual FL application loading and broader host integration |
| VL Balance experimental FL C++ interface | Intact FL engine loader accepts rebuilt module; 21 unchanged adapter methods and 20 callback slots; original AppKit controls/meters, host adapter callbacks and worker-thread regression checks | Full application/project/mixer and VL Studio integration; original VCL/artwork parity |
| Fruity Mute 2 subset | Independent C ABI and experimental native factory; original-factory audio/state comparisons; intact engine loader, 20 callback slots and synthetic stream checks | Editor, real application state-stream ABI, application/project/mixer and VL Studio integration |
| 3x Osc small DSP engine | All 45 public exports; generated wavetables/mipmaps, FFT, public class ABI, custom waves, rendering and serial multi-instance lifecycle checks | Full Fruity wrapper, polyphony, modulation, editor and application hosting |
| 3x Osc wrapper subset | 114 control slots, version-14 state field storage, HQ/legacy raw voice rendering and multi-voice lifecycle; bounded original-factory comparisons | Integrated-editor envelopes/filter/modulation, final mixing, native factory ABI, GUI and application hosting |
| Vital upstream source | Private GPL Vial 1.0.6 arm64 VST3/AU source builds, native MIDI/audio and captured state checks; narrow deterministic audio comparison with installed Intel Vital 1.0.7 | Version gap, legacy VST2 SDK dependency, full preset/parameter/layout/rate/GUI tests; disclosed sample-state bug fix changes original behavior |
| Other installed plugins | Identity, architectures, dependencies and factory inventory; further native analysis underway | Independent source reconstruction, native builds, processing/state/UI tests and critique |

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

The successful cases are finite disclosed test domains. Matching export names
or compiling all identified functions does not prove arbitrary input, exception
unwinding, resource, GUI or whole-plugin equivalence. Source and native binary
hashes bind the local evidence to the inspected installation.

Use the [effects](effects/README.md), [generator](generators/README.md) and
[native host](common/README.md) instructions to reproduce their respective
checks. Original reconstruction code is published; target binaries, machine
code slices, commercial assets, decompiler outputs, captured states and
external GPL/SDK source remain outside this MIT repository.

The [ownership and acceptance plan](../../docs/PLUGIN_RECONSTRUCTION_PLAN.md)
defines the implementation → independent critique → repair → verification loop.
