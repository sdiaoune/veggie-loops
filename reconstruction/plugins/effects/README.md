# Balance numerical reconstruction

This independent C++ implementation reconstructs the inspected Fruity Balance
stereo DSP callback and the numerical set/get subset of its parameter callback.
Full editor and FL application loading parity have not been established.
`balance_plugin.h/.cpp` provides an original
C ABI with create/destroy, sample rate, normalized automation, resume, validated
8-byte state save/restore and render/meter functions around this implementation.
This API has its own symbol names and does not claim the FL/VST/AU entrypoints.

Run the portable model checks:

```sh
./reconstruction/plugins/effects/verify.sh
```

On macOS arm64 with the inspected FL Studio 2024 installation, run the
identity-bound differential checks:

```sh
./reconstruction/plugins/effects/verify.sh --native
```

The native test first checks the universal source, arm64 slice and each of eleven
function-body SHA-256 identities. It maps the unchanged numerical callback
bodies privately, resolves their system math imports, and uses local success-only
exception-frame and zero-string cleanup stubs. It never loads the plugin factory
or licensing code. Original bytes and compiled replay files stay in ignored
`.tools/`. A different installed plugin version is rejected.

The checked domain uses finite, interleaved float stereo buffers, 0–1024 frames
at the explicit tested lengths, separate or exactly identical buffers, aligned
and 4-byte-offset storage, signed-zero coefficient cases, 4-block state sequences,
integer pan values −128 through 128 and volume values sampled from 0 through
synthetic maxima 256, 320 and 640. Numerical parameter flags 1 (set) and 2 (get)
are supported. The synthetic maximum is not a recovered factory default. Partial
buffer overlap, nonfinite input, UI/normalization flags, exceptions and alternate
architectures are outside this numerical replay proof. The factory test below
separately verifies the real volume maximum and normalized automation.

The verified build reports 19,200 DSP calls (2,076,480 frames) and 81,212
numerical parameter calls with bit-identical outputs and observed state. The
meter preserves the native tail behavior: complete groups of eight frames use
absolute peaks, while a remaining tail compares signed samples with zero.

Use the script's exact floating-point compiler flags: `-std=c++20 -O2
-ffp-contract=off -fno-fast-math -fno-builtin-sin -fno-builtin-cos
-fno-builtin-exp`. Clang's combined sin/cos
builtin changes some results by one ULP; the script preserves the inspected
plugin's separate imported `sin`, `cos` and `exp` calls. Full plugin parity has
not been established by these callback tests.

The separately requested full-instance check creates and destroys the installed
original plugin and compares its real native controls, normalized automation,
state stream, resume and audio callbacks with the independent model:

```sh
./reconstruction/plugins/effects/verify.sh --factory
```

This check also loads a newly compiled independent C ABI dylib and compares it
through exported functions with the live original plugin. It runs in a local
process with a synthetic host and real original VCL
controls; it does not show the editor or load a rebuilt plugin in FL Studio.
It verifies factory defaults (pan 0, volume 256), native ranges (pan −128..128,
volume 0..320), 1,024 parameter/control calls, 205 valid state restores and
43,441 actual callback frames. Normalized MIDI input spans 0..2^30. State restore
range rejection in the C ABI is an intentional input-validation extension and
has no equivalence claim for malformed source states.

The experimental `balance_native_abi.h/.cpp` adds an independent native FL C++
factory and function table. Its original interface description follows measured
engine adapter offsets and the documented SDK boundary. It includes numerical
parameters, state transfer, sample rate, resume, name and effect callbacks, with
safe no-op callbacks for unused generator/voice functions. Its default build has
no editor; an optional independently written AppKit editor is described below. The plugin and
parameter names are original to Veggie Loops.

```sh
./reconstruction/plugins/effects/verify.sh --engine-abi
```

This identity-bound check maps 21 unchanged FLEngine adapter routines privately
and forwards calls through them into the compiled `VLBalanceNative.dylib` factory
object. It checks 1,200 sequences and 140,700 stereo frames against direct calls
to another instance, including control flags 17/49, state, sample rate, resume,
names and destruction. All 20 public callback slots are exercised, including
the unused effect voice/generator/MIDI no-ops. The engine loader statically selects its C++ adaptation
path when `SetExternalAppHandle` is absent; the rebuilt library deliberately
exports `CreatePlugInstance` as its native factory. This proves the inspected forwarding boundary.
The FL Studio application has not loaded the rebuilt plugin, and no VST or AU
bundle is provided by this wrapper.

The actual native engine DLL loader check loads the intact inspected engine and
invokes its measured loader with an immutable managed UTF-16 path to the newly
compiled plugin. It uses the real engine host and plugin adapter constructors,
checks 2,400 parameter calls and 140,700 stereo frames, and frees the real plugin
wrapper after destroying the compiled object. No application instance is created;
the numerical factory makes no callbacks through the supplied host interface.

```sh
./reconstruction/plugins/effects/verify_engine_loader.sh
```

The actual engine state-stream check constructs its real memory and COM stream
adapter classes, then saves and restores both rebuilt effects through real plugin
wrappers. It proves 32-bit HRESULT and completed-count handling, including failed
HRESULTs that report full byte counts without allowing state changes:

```sh
./reconstruction/plugins/effects/verify_engine_stream.sh
```

The check performs 256 saves and 256 restores across Balance and Mute 2. The
scope and remaining application/project routing gates are in `ENGINE_STREAMS.md`.

`balance_editor.h/.mm` is an independently written AppKit editor with pan and volume controls,
gain labels, peak meters and an explicit host locking/notification interface.
The native wrapper includes it when built with `VL_BALANCE_APPKIT_EDITOR=1` and
advertises the documented NSView parent flag. Its controls update the verified
numerical state, then notify the host after unlocking. Host automation and meters
refresh during GUI Idle. Resize notification is deferred until Idle so that the
real engine adapter has copied the newly attached editor handle first.
Tick and MIDI tick callbacks do no GUI work; Idle skips editor and host state
when invoked off the main thread. All editor operations, hint flags and native
plugin destruction while an editor exists must run on the main thread. An
off-main destruction attempt preserves the object and attached view until a
main-thread retry; the module and host must remain alive until that retry
finishes. Numerical callbacks require serial access or the host's mix lock.

```sh
./reconstruction/plugins/effects/verify_editor.sh
```

This check uses the intact engine's real plugin and host adapter classes with a
synthetic Pascal host. It exercises control changes, hint flags, automation,
audio/meter refresh, resize ordering, detach, reattach and destruction. Worker
tick, MIDI tick and Idle calls are verified to leave a pending resize for main
Idle, and off-main destruction is verified to preserve the attached editor.
No original
VCL resources or artwork are included. Original GUI parity, actual FL application
and mixer integration, x86_64, VST/AU formats and 82 other effect families remain
open; a complete plugin reconstruction is not certified by these checks.
