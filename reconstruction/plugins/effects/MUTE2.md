# Mute 2 reconstruction

`mute2_plugin.h/.cpp` implements an independent numerical C API for the inspected
Fruity Mute 2 behavior. Both raw parameters span 0..1024 and start at 512.
The first enables audio at values 512 and above; lower values mute the selected
left, both or right channels. Muting one channel multiplies it by zero and
preserves signed zero; muting both channels writes positive zero. Version 1 state
contains a version word and two raw values, totaling 12 little-endian bytes.

Run the original-factory differential test on macOS arm64 with the inspected
FL Studio 2024 installation:

```sh
./reconstruction/plugins/effects/verify_mute2.sh
```

The fixture checks the installed universal binary identity before loading its
unaltered factory in a synthetic host. It compares a newly compiled independent
C API dylib with real original controls and callbacks: 10,248 parameter/control
cases, 512 valid state restores and 4,610 audio calls totaling 495,472 stereo
frames. Both integer parameter ranges are exhausted. Normalized MIDI automation
includes every rounding tie and either adjacent integer, plus endpoints.
Separate, exactly aliased and 4-byte-offset buffers include signed-zero samples
and untouched guard bytes. The factory state shim verifies the original's valid
4-byte plus 8-byte framing; its original completion-count arguments are null.

The declared numerical domain uses finite stereo floats, 0..1024 frames,
disjoint or identical buffers, valid raw values and normalized MIDI input
0..2^30. Normalization uses the default nearest-even FP environment. Calls on
an instance must be serialized or protected by the host's mix lock. Invalid
ranges, state versions, partial overlap and nonfinite input are rejected by this
independent API; malformed original inputs have no equivalence claim.
The compiler flags are `-std=c++20 -O2 -ffp-contract=off -fno-fast-math`.

`mute2_native_abi.h/.cpp` adds a separate native FL C++ factory using the
independently measured arm64 interface declaration shared with Balance. It has
original VL Mute 2 names, numerical parameters, state and effect callbacks,
with explicit no-ops for editor and unused generator/voice/MIDI functions.

```sh
./reconstruction/plugins/effects/verify_mute2_engine_loader.sh
```

This test loads the intact inspected FLEngine and uses its actual DLL loader to
create and free a real engine wrapper around the newly compiled native dylib.
It exercises all 20 callback slots, 2,400 parameter calls, 1,200 state saves,
240 state restores and 140,700 stereo frames. State streams in this fixture
have synthetic 64-bit length and completion-count fields; short-read rejection
preserves numerical state. The count width of the actual application's native
stream remains unverified. These native checks establish loader and forwarding
behavior within that declared fixture.

The numerical C API passed independent source review and factory replay. The
native loader and synthetic stream fixture also passed independent compilation
and replay, recorded in `mute2-verification.json`.
No original resources or artwork are included. Original editor/hints,
application/project/mixer integration, complete state-stream host compatibility,
x86_64 and VST/AU packaging remain open. This is a verified numerical and native
loader reconstruction milestone; whole-plugin equivalence is not certified.
