# VL Soft Clipper numerical reconstruction

This independently written C API reproduces the measured two-control processing
of the pinned arm64 Fruity Soft Clipper. The original factory, controls and valid
state framing are exercised directly. It is a partial numerical reconstruction;
native FL loading, editor, actual application/project/mixer hosting, VST/AU and
whole-plugin equivalence remain separate gates. Independent review status and
exact source hashes are recorded in `soft-clipper-verification.json`.

```sh
./reconstruction/plugins/effects/verify_soft_clipper.sh
```

The source factory was created and destroyed with a synthetic Pascal host and
path manager. Its threshold control ranges from 1 to 127, defaults to 100 and
normalizes with scale 1/126. Postgain ranges from 0 to 160, defaults to 128 and
normalizes with scale 1/160. The DSP maps both raw values with float scaling by
1/128. Normalized MIDI integers use double scaling by 2^-30 and nearest-even
rounding, followed by the control minimum.

The knee uses a float threshold, float spread `1-threshold` and float reciprocal
spread. Above threshold, a float exponent argument feeds system double `exp`;
separate double multiply/add produces the clipped magnitude before conversion
to float. Input sign is restored through comparison with zero, which maps
negative zero to positive zero. Postgain uses the measured float ln(11) and
float 0.1 constants around a double exponential expression. Raw 128 explicitly
selects gain 1.

The pre-postgain stereo peak meter accumulates across blocks. The measured NEON
helper takes absolute values for full groups of eight stereo frames; its signed
tail ignores negative samples. The numerical API has independent enable/clear
controls, tested against synthetic source-object meter fields. Original GUI
meter timers, displays, resets and editor behavior remain unverified.

Valid state is eight little-endian bytes containing threshold and postgain raw
words, without a version header. The commercial factory transfers eight bytes
once with a null completion output. Our C API validates ranges and exact length
atomically; malformed-input rejection is an independent extension. The fixture
stream uses 32-bit completion stores when requested, but this factory comparison
only measures original valid framing and does not instantiate engine streams.

The canonical replay compares the compiled C API, the independent numerical
model and original factory over 31,480 parameter/control cases, 31,874 render
callbacks and 3,422,287 stereo frames. It includes every threshold/postgain pair,
all supported numerical flag combinations, normalized MIDI values/endpoints
and exact rounding ties, 512 valid restores, 31,994 state
saves, 40 synthetic meter-state sequences and 75 atomic invalid-input cases.
Every main guard is checked against its pre-call bytes; exact alias, disjoint
buffers, four-byte offsets and disjoint source immutability are covered. Sizes
include 0, 1, odd values, vector boundaries and 1,024 frames. Invalid API cases
cover ranges, flags, null pointers, lengths, partial overlaps, nonfinite samples
and samples outside the declared amplitude domain. Rejected source inputs are
never sent to the commercial factory.

Caller result/sample/state/meter buffers must use valid readable/writable
storage outside the live instance. Overlapping ranges reject before caller
buffer access, including a zero-frame buffer beginning inside the object.
This is an independent ABI validation extension. The focused regressions pin
the complete own object bytes in addition to state, meters and caller output.

All instance access requires serialized calls or the host mix lock. Render
requires finite float stereo samples with absolute input at most 16 and
0..1,024 frames, with valid exactly identical or disjoint buffers. Tested math
uses macOS arm64 26.6.2 build 25G83, Apple clang 21.0.0 (clang-2100.3.34.2), system
libm and flags `-std=c++20 -O2 -ffp-contract=off -fno-fast-math
-fno-builtin-exp`. Exact comparisons are scoped to this environment, nearest-even
rounding and the pinned binaries. NaN/Inf, alternate FP environments and other
architectures remain outside the numerical equivalence proof. The factory
fixture refuses non-macOS-arm64 compilation and checks both target and mapped
DSP dependency SHA-256 before execution. No target runtime, GUI resources or
raw decompiler output are distributed.
