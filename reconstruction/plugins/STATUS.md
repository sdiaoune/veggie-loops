# Plugin reconstruction status

Full reconstruction is **incomplete**. No full FL Studio application or
complete installed plugin is certified. The workstation's existing native
audio engine and instruments remain its original implementation.

| Component | Independently built and checked milestone | Remaining work |
| --- | --- | --- |
| Fruity Balance numerical core | Bitwise audio/parameter comparison, independently built C ABI, original-factory control/state/lifecycle comparison | Complete editor/hints, actual FL application loading, broader host integration |
| VL Balance experimental FL C++ interface | 21 unchanged FL engine adapter methods and 20 callback slots forward into the independent wrapper; bounded factory, parameters, state, audio and destruction checks | Full application loader/editor contracts and VL Studio integration |
| 3x Osc small DSP engine | All 45 public exports; generated wavetables/mipmaps, FFT, public class ABI, custom waves, rendering and serial multi-instance lifecycle checks | Separate Fruity wrapper, polyphony, automation, presets, editor and application hosting |
| Vital upstream source | Private GPL Vial 1.0.6 arm64 VST3/AU source builds, native MIDI/audio and captured state checks; narrow deterministic audio comparison with installed Intel Vital 1.0.7 | Version gap, legacy VST2 SDK dependency, full preset/parameter/layout/rate/GUI tests; disclosed sample-state bug fix changes original behavior |
| Other installed plugins | Identity, architectures, dependencies and factory inventory; further native analysis underway | Independent source reconstruction, native builds, processing/state/UI tests and critique |

The standard-path external inventory contains 12 top-level bundles: five VST2,
two VST3 and five AU. These represent FL Studio wrappers, LABS, Purity, Vital
and TyrellN6. The bundled native inventories contain 84 effect families and
49 generator folders. Counts include wrappers and shared engines and must not
be interpreted as independent reconstructed products.

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
