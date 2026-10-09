# Phase Inverter reconstruction

`phase_inverter_plugin.h/.cpp` implements an independently written numerical
C API for the inspected Fruity Phase Inverter behavior. Its single raw parameter
spans 0..1024 and starts at 1024. Values 0..341 bypass inversion, 342..682 invert
the left channel and 683..1024 invert the right channel. The recovered mapping
rounds the float expression `3 * unit - 0.5` to nearest even. Inversion toggles
the selected channel's sign bit, preserving zero signs and all NaN payload bits.
Version 1 state is a version word followed by the raw value: eight little-endian
bytes. Restore also accepts valid version 0 states.

```sh
./reconstruction/plugins/effects/verify_phase_inverter.sh
```

The identity-bound macOS arm64 fixture constructs and destroys the installed
original factory with its real VCL control and a synthetic host. It compares a
freshly compiled C API dylib over 4,099 parameter/control cases, 512 valid state
restores and 2,561 audio calls totaling 274,830 stereo frames. The complete raw
range and every normalized MIDI rounding tie plus adjacent inputs are tested.
Sample classes include signed zeros, subnormals, infinities, quiet and signaling
NaNs with payloads, plus random sample bits. Separate, identical and four-byte
offset buffers preserve guard bytes. Factory state streams verify the original
4-byte plus 4-byte framing with null completion outputs.

The numerical API supports valid interleaved 32-bit stereo float storage with
every sample bit pattern, 0..1024 frames and separate or identical buffers.
Parameter normalization requires the default nearest-even FP environment;
calls on an instance are serialized or protected by the host mix lock. Invalid
ranges, state versions and partial overlaps are rejected atomically as an
independent validation extension. The compiler flags are
`-std=c++20 -O2 -ffp-contract=off -fno-fast-math`.

`phase_inverter_native_abi.h/.cpp` adds a separate native FL C++ factory using the
measured engine interface shared with Balance. The default native build has no
editor and makes no host callbacks. `VL_PHASE_INVERTER_APPKIT_EDITOR=1` adds the
independently written AppKit editor. Numerical, name and state callbacks are
implemented; unused generator, voice and MIDI operations are explicit no-ops.
It uses original VL names and has no commercial plugin identifier.

```sh
./reconstruction/plugins/effects/verify_phase_inverter_engine_loader.sh
./reconstruction/plugins/effects/verify_phase_inverter_engine_stream.sh
```

The first fixture invokes the intact inspected engine's DLL loader and creates
and frees its real wrapper around a newly compiled native library. It exercises
all 20 callback slots, 1,200 parameter calls, 1,200 state saves, 240 restores,
short-second-read rejection and 140,700 stereo frames. Its synthetic streams use
the measured 32-bit HRESULT, length and completed-count boundary.

The second fixture constructs the intact engine's actual `TMemoryStream` and
`TStreamAdapter` classes and real plugin wrapper. It performs 128 saves and 128
restores. Read/Write completion stores preserve the adjacent high 32-bit sentinel;
the provider's invalid-buffer error is a negative 32-bit HRESULT. A synthetic
provider reporting a full count with a failed HRESULT is rejected without
changing parameters, on either the first or second read. The shared protocol is
described in `ENGINE_STREAMS.md`.

The AppKit editor is tested through its own numerical API and the intact
engine's real plugin and host adapters:

```sh
./reconstruction/plugins/effects/verify_phase_inverter_editor.sh
```

Its Bypass/Left/Right selector drives verified numerical parameters. All 1,025
raw automation displays are compared with actual rendered channel polarity.
Notifications follow host unlocking. GUI, hint and destruction calls require
the main thread; a refused off-main destruction preserves the view for a
main-thread retry. The native fixture uses a synthetic Pascal host, drives all
three selector choices through real audio callbacks and verifies automation
edges, hint flags, deferred resize ordering, detach, reattach and destruction.
Worker tick, MIDI tick, Idle and hint callbacks skip GUI; native destruction
in an optional-editor build requires the main thread even before first attachment.
A refused native destruction preserves
the numerical instance and attached view. Keep the module, numerical instance
and host context alive until the main-thread retry succeeds.

The numerical factory replay, current native loader and real stream checks,
standalone and native editors passed independent compilation and review. The
maintained manifest binds the reviewed source and its tested scope. Original
VCL controls, artwork and resources are not
redistributed. Full application/project/mixer hosting, original editor/hint
parity, project/preset envelopes, x86_64 and VST/AU formats remain open.
Whole-plugin equivalence is not certified.
