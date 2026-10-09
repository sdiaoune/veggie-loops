# VL Stereo Shaper

This independently written numerical layer reconstructs six Stereo Shaper controls,
the nonlinear stereo matrix and coefficient slew, a selected-channel delay ring,
and the selected-channel all-pass filter. It compiles into an original C ABI
library. Native FL loading, its editor, projects, mixer integration, VST/AU, and
whole-plugin equivalence remain unverified. No commercial code, artwork, presets,
or binary files are included.

Run on the measured macOS arm64 installation:

```sh
./reconstruction/plugins/effects/verify_stereo_shaper.sh
```

The fixture creates and destroys the installed commercial plugin through its real
factory, instantiating its actual six controls. It compares that plugin against
the separately compiled C ABI. The fixture pins the original universal plugin
and its IPP DSP dependency by SHA-256 and refuses Intel/Rosetta compilation before
calling the measured arm64 layouts. The original app and plugin are read-only.

Current local replay passes 75,833 raw/normalized parameter changes, 128,395 render
callbacks containing 436,923 stereo frames, and 257 valid original state restores.
The corpus covers every raw matrix-gain value on one matrix control (all four
matrix controls also change together in random transition sequences), every raw
delay and phase value, getter/control-value agreement, normalized random units
and endpoints, zero/odd/vector-boundary frame counts, signed zero, asymmetric
channels, exact alias and disjoint buffers, and four-byte offsets. Five sample
rates, both pre/post modes, coefficient transitions and resume are replayed.
Independent numerical review passed this corpus. Separate source-only sanitizer
checks passed 51 invalid calls and seven injected allocation failures, preserving
the complete numerical/delay/filter state and result values. These numbers
describe the checked corpus and domains.

The fake Pascal host supplies four output slots. There are 768 side-output
protocol sequences covering indices 1, 2, and 3. The original requests its output
through measured VMT slot `0x1f0`, first with flags 0 and then 1, and adds
`dry - processed` when a buffer is supplied. Both supplied and null buffers are
replayed. The own C ABI exposes this numerical contribution through its optional
side buffer. A separate native wrapper and actual engine adapter replay are
described in [STEREO_SHAPER_NATIVE.md](STEREO_SHAPER_NATIVE.md); this numerical
factory fixture establishes the original callback's protocol with a synthetic
host. Actual application routing remains open.

Raw defaults are `[0, 12800, 12800, 0, 0, 0]`; matrix ranges are -25600..25600,
delay/phase ranges -4096..4096. The observed 36-byte little-endian save payload
contains version 0, six raw values, a side-output index, and a pre/post selector.
The source transfers 4 and 32 bytes with null completion pointers. Its restore
updates the original controls and recalculates delay/filter state. Stream proof
currently uses valid framing only; actual engine stream/error integration remains
open. A source factory with four outputs clamps its initial inactive send to 0;
a prior zero-output probe held -1. The own API explicitly models four outputs.

Each instance requires serialized calls or the host mix lock. Audio is limited
to finite interleaved float samples with magnitude at most 4, 0..1024 frames,
and the five documented rates. Main buffers may be identical or disjoint; a
provided side buffer must be disjoint from both. Malformed state and overlapping
buffer rejection are independent validation extensions. No unrestricted claim
is made for NaN/Inf, alternate FP environments or arbitrary host output counts.

Bit comparisons use Apple's arm64 system libm and these exact numerical flags:
`-std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-sin
-fno-builtin-cos -fno-builtin-exp`. Source instruction evidence required explicit
double operations around float conversions; superficially equivalent float
expressions differed by one bit. Raw decompiler output and local target slices
are kept in ignored evidence/build directories. The maintained implementation
was written independently from measured behavior and instruction obligations.
