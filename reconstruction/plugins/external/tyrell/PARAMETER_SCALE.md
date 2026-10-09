# TyrellN6 parameter range and conversion subset

This original MIT source reconstructs the installed x86_64 TyrellN6 VST's
92 public parameter descriptors and the arithmetic of its outer setter/getter.
It is a bounded partial reconstruction. The actual parameter manager, voices,
DSP, preset/state format, GUI, automation scheduling and VST/AU factories are
unfinished. No target binaries, decompiler text, presets, assets or SDK are
distributed.

Run the source contract and original-callback comparison on the pinned Mac:

```sh
./reconstruction/plugins/external/tyrell/verify-parameter-scale.sh
```

The script builds a source-only ASan/UBSan contract fixture for the current
architecture and an ad-hoc-signed x86_64 native fixture. The latter requires
Rosetta on an Apple Silicon Mac. It hashes the installed universal binary
before loading it, rejects a changed identity, and checks the actual factory
and public parameter callback addresses against the reviewed Intel slice.
The installed plugin may write its usual preferences and log during factory
creation/destruction. The fixture opens no editor and sends no audio or MIDI.

The descriptor table contains public ordinal, internal identifier, minimum and
maximum. The new lookup accepts ordinals 0..91 or 10000 plus one of these same
92 identifiers. Other internal descriptors remain outside this subset.
The native fixture compares every field with the original manager, and verifies
that these public/internal lookups identify the same original descriptor.

The setter at `0x3b680` uses three separate float operations:
`(maximum - minimum) * normalized + minimum`. It forwards the descriptor's
identifier and flag 0 to the manager. The getter at `0x3b740` first asks the
manager for the original, undecoded parameter index, default float 0 and flag 1.
It then uses the decoded descriptor to return `(raw - minimum) / extent`.
A zero-width range returns its minimum, including the sign of zero. Ordinary
descriptor lookup uses flag 1; indices at least 10000 subtract that value and
use flag 0. The public VST callbacks at `0x3c300` and `0x3c320` reach these
methods through the native object's own dispatch.

Two complementary native comparisons are retained. Unmodified-manager writes
cover ten normalized values per public descriptor, followed by an original raw
read and a bit-exact rebuilt/public-getter comparison. Separately, an isolated
instance-local manager vtable supplies controlled descriptor/raw values to the
actual outer VST callbacks and records their forwarded arguments. It compares
both public and known internal index paths for each descriptor, with 513
normalized values from -2 to 2. These controlled cases deliberately suppress
the GUI branch and replace manager behavior; they prove outer conversion and
forwarding, without claiming a rebuilt parameter manager or the manager's
quantization/clamping. The original manager and GUI pointers are restored
before any real-manager or lifetime call. Twelve synthetic zero-width cases
also exercise the actual original getter with signed zero and nonzero minima.

The new C API supports finite ordered endpoints with absolute value at most
512, normalized setter values in [-2,2] without clipping, and finite getter raw
values with absolute value at most 4096. It rejects a non-finite computed result
before writing the output. Its checked failures preserve the caller's output;
invalid arguments are never sent to the native ABI. Writable output storage is
the caller's responsibility. Nearest-even rounding, gradual underflow
(FTZ/DAZ/FZ disabled), and compilation with
`-ffp-contract=off -fno-fast-math` are required. The original manager's malformed
input behavior, other compilers/platforms/rounding modes, original GUI side
effects and full plugin equivalence remain unverified.
