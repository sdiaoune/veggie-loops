# TyrellN6 raw storage getter

`vl_tyrell_raw_get` independently reconstructs one getter over caller-owned
storage. It follows the actual getter's descriptor flags, full signed32 type,
public/internal map, special target records, integer pointees, meter pointees
and raw float cache. Float loads preserve their bits; integer conversion uses
nearest-even. Incoming fallback is ignored, as in the measured native method.
The header defines valid storage, count, serialization, FP and output-alias
requirements. Defensive malformed-input rejection is an additional C API
contract, rather than proof of malformed native behavior.

The runtime, header and two tests are byte-identical to the independently
reviewed corrected private candidate. This adds a storage primitive; existing
parameter-scale and prepared-manager modules are unchanged. The prepared
manager forwards fallback to its controlled backend, while this actual getter
ignores fallback. It does not reconstruct the real notifier or its scheduling.

On the identity-bound Intel target, manager offsets `0x40` and `0x48` select
the same receiver. Its getter slot `0x2d8` reaches image offset `0x153620`.
The live configuration supplies 213 internal descriptors, 82 special records
and 92 public indices. Native comparison covers all routes: 82 special,
84 integer-pointee, 13 meter-pointee and 34 cached-float IDs.

Run on macOS with Clang, Rosetta and the locally installed original:

```sh
sh reconstruction/plugins/external/tyrell/verify-downstream-getter.sh
```

The recipe builds the source and both fixtures with fatal ASan/UBSan checks,
signs the owned Intel executable before execution, and rejects sanitizer
diagnostics before producing a verification result. Outputs stay under
`.tools/plugin-work/external/tyrell/downstream-public-getter-check`.
The source-only fixture checks 4,119 successes and 696 atomic rejections.
The unchanged actual factory supplies 2,440 reads across all internal/public
IDs and eight fallback payloads. Another 4,160 cases temporarily change one
four-byte scalar per route, restoring its original bits before any other
native callback or destruction, including failure unwinding. Those arbitrary
bits establish getter loads/conversion, rather than valid DSP or preset data.
The original factory can write its ordinary log, preferences and MIDI caches.

The native fixture pins the installed universal binary SHA-256
`a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54`.
The original binary is not instrumented. An independent reviewer also tested
250,000 source route/bit cases, 33,280 actual-native oracle cases, 1,040 public
route cases, and a failing truncated-descriptor-type mutation.

An earlier fixture emitted seven unaligned pointer-table UBSan diagnostics
while recovery allowed success JSON. That result is rejected and preserved
locally under `downstream-getter-rejected-ef361da2`; corrected pointer reads use
byte copies and the recipe now fails closed. Verification records bind both
the rejected evidence and the clean replacement; no captured binary, preset,
asset or decompiled source is distributed.

Real notifier clipping, queue/DSP/audio scheduling, native class/factory
reconstruction, state, GUI, whole DSP/plugin equivalence, FP exception-flag
equivalence and realtime guarantees remain unproved. Independent copied-source replay has accepted this bounded component.
