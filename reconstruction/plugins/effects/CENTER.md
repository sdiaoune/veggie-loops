# VL Center numerical reconstruction

This independently written C API reproduces the pinned arm64 Fruity Center's
one-control centering filter. The original factory, enable control, processing,
rate changes, resets and valid preset transfers are compared directly with a
compiled own numerical library. It remains a bounded partial reconstruction.
Rebuilt native factory/loading, real host streams, own/original editor, remaining
source metadata/names/dispatcher/events, actual FL application/project/mixer
hosting, x86/VST/AU and whole-plugin equivalence are separate gates.

```sh
./reconstruction/plugins/effects/verify_center.sh
./reconstruction/plugins/effects/verify_center_boundary.sh
```

The first check requires the pinned installed macOS arm64 target. The second
runs only independently written source under AddressSanitizer and
UndefinedBehaviorSanitizer, without loading commercial binaries. The runtime,
header and both fixtures are byte-identical to the independently accepted
private candidate. The numerical script changes only name/source/output paths;
the separate sanitizer script reproduces the accepted source-only command.
Source identities and review scope are in `center-verification.json`.

## Numerical behavior

Enable is raw 0 or 1, default 1. Normalized integers 0..2^30 scale with double
2^-30 and nearest-even rounding; set has priority over get. The own API supports
flags 0/1/2/3/32/33/34/35 and index 0. Source GUI updates and hints are excluded
from this numerical flag contract.

Each channel retains a double position and velocity. For each float input,
velocity adds `(input-position)*step`; position adds that velocity; velocity
then multiplies by the measured float damping `0x1.eb851ep-1`. Float output is
`input-position`. These are separate double operations with contraction off.
The step is a float conversion of
`(44100.0/sample_rate)*0x1.327c766a8cde1p-18`.

After every enabled block, absolute position and velocity values strictly
smaller than 2^-24 become positive zero. This also happens for zero frames.
The flush threshold is larger than denormal magnitudes, so block boundaries can
affect retained history. Bypass copies sample bits and preserves the filter
history. Rate changes update only the step; resume clears the filter history
while preserving enable and coefficients. The own filter-state getter returns
left/right position followed by left/right velocity for numerical inspection.

Valid state consists of eight little-endian bytes: a 32-bit version and a
32-bit enable value. Save writes version 1; restore accepts valid versions
0 and 1 with enable 0 or 1. The original factory performs two four-byte stream
transfers with null completion outputs. Restoring enable preserves filter
history and sample-rate coefficients. Own validation of malformed bytes/ranges
is an independent extension; malformed inputs are never sent to the original
factory.

## Coverage and limits

| Source function | Measured numerical proof | Open scope |
| --- | --- | --- |
| Factory `0x6110` / `0x312a0`, constructor `0x31580` | Original factory creates/destroys; control range/default and numerical defaults match. | Rebuilt native class and original VCL/host lifecycle. |
| Parameter `0x31830` | Raw values, supported flags, normalized endpoints and rounding ties match. | Original UI/hint timing and other flags. |
| Render `0x31ae0` / kernel `0x133d80` | Sample bits and all four used double-state fields match; actual kernel and copy dependency identities checked. | Other FP/compiler domains and native application hosting. |
| Reset `0x133bd0` / `0x31b70` | Used runtime clears; four unused source doubles remain zero. | Other embedded filter operations. |
| Rate `0x31540` / utility clock `0x134e80` | Native step matches and history survives rate changes. | Complete utility-clock/base-host behavior. |
| State `0x31410` | Valid two-transfer framing and versions 0/1 match without clearing history. | Real host stream/error/application lifecycle. |
| Dispatcher `0x31320` | Numerical resume 2 and rate 4 paths compared. | Original attach 0 and remaining dispatch/name/event semantics. |

The canonical fixture covers 1,169 parameter cases, 5,493 callbacks and
1,516,707 stereo frames, including long uninterrupted constant/silence sequences,
62 sample-rate changes, 46 resets, 257 saves and 256 restores. All sample guards
are checked against their pre-call values; exact alias, disjoint buffers,
four-byte offsets and disjoint input immutability are covered. Sizes include
0/1/odd/boundary values through 1,024 frames. One hundred explicitly synthetic
runtime cases test strict flush boundaries, signed zeros, bypass preservation
and zero-frame behavior. The fixture installs only known four-double source
fields and the asserted trivially copyable own Processor representation for
those cases; this does not expose a public mutable filter-state API.

Seventy-seven invalid API cases preserve the complete own instance and relevant
caller outputs. The separate sanitizer fixture checks 342 overlapping result,
state, filter-state and sample buffer intervals plus six enabled/bypass nullable
zero-frame calls. Independent critique additionally checked all eight nullable
zero-frame combinations, twelve history-preservation cases and sixteen flag
priority cases. The numerical manifest retains that review separately from the
canonical counters.

Every instance access, including getters/save/destruction, requires serialized
calls or the host mix lock. Render accepts finite float stereo input with
absolute value at most 16 and 0..1,024 frames; rates are integer 8,000..384,000 Hz.
Buffers must be valid readable/writable storage external to the live instance.
Exact alias and disjoint sample buffers are supported. Partial overlaps and
ranges overlapping the instance reject before access, including zero-frame
sample pointers starting inside it. Null sample buffers are allowed only for
zero frames. The unchecked numerical class assumes these contracts; public C
API validation implements rejection. No unrestricted threading or realtime
certificate is claimed.

Tested numerical math uses default nearest-even rounding, macOS arm64 26.6.2
build 25G83 and Apple clang 21.0.0 (clang-2100.3.34.2), with
`-std=c++20 -O2 -ffp-contract=off -fno-fast-math`. NaN/Inf equivalence, alternate
FP/compiler environments and other architectures are unverified. The native
factory fixture refuses compilation outside Apple arm64, verifies original
universal and mapped DSP dependency SHA-256, then validates the actual centering
kernel and `ippsCopy_64s` binding before callbacks. Extracted arm64 identities
are retained in the manifest. Commercial binaries, resources and raw
pseudocode are excluded from distributed source.
