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

Use the script's exact floating-point compiler flags. Clang's combined sin/cos
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
safe no-op callbacks for unused generator/voice functions. It currently has no
editor or hint UI. The plugin and parameter names are original to Veggie Loops.

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
The full native engine loader and FL Studio application have not loaded the
rebuilt plugin, and no VST or AU bundle is provided by this wrapper.
