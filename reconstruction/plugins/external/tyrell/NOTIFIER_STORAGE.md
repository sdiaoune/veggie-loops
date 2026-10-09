# TyrellN6 bounded notifier storage

This independently written prepared C API reproduces bounded scalar decisions
of the installed Intel notifier: clipping, type selection, cached values,
special target/increment/remaining records, and queue insertion. It exposes
static callback-request bits; it does not execute the native unit callbacks.
The accepted private implementation, header and two fixtures are copied here
byte for byte. This public recipe requires the installed original for native
comparisons; root's final-path review is pending.

Run `sh reconstruction/plugins/external/tyrell/notifier-verify.sh`. Outputs go
to the separate ignored `.tools/plugin-work/external/tyrell/notifier-public-check`
directory. Source and fixtures use fatal ASan/UBSan, nearest-even rounding,
gradual underflow, separate operations and no fast math. The Intel fixture is
ad-hoc signed and signature-verified before execution. Installed native code
is uninstrumented. The header defines the complete prepared input and atomic
rejection contract, including initialized external storage, bounded finite
values, serialized access and disjoint descriptor/state/result spans.

The pinned universal binary SHA is
`a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54`.
Manager offsets 0x40 and 0x48 point to the same receiver. VFT slot 0x298 selects
forwarder 0x154430, which zero-extends the force byte and calls slot 0x2c8,
notifier 0x154450. Actual method arguments are receiver, ID, force, float value
and float clock. The original factory, VFT, descriptors, maps, native unit
callbacks and allocated storage remain intact in the native comparisons.

Low-byte types 3/4 ignore writes before clipping; this differs from the raw
getter's full-type discrimination. This API models full types 0/1 plus those
ignored types. Other types, including callback-dependent type 5, reject.
Integer values use `floorf(value + 0.5f)`. Flag 2 routes to a special 16-byte
record. Flag 0x200 chooses a shorter cyclic difference using the descriptor
maximum, with strict absolute comparison on ties. New queued targets use 50
steps and 0.02f gain; immediate targets use 1 step and gain 1. Equal targets
retain motion fields. Unqueued stale motions reset, and unqueued zero
difference sets dirty and forces immediate completion. Queue capacity errors
reject before any source state or result changes.

Factory queue count -1 forces immediate behavior. The controlled queue corpus
does not prove active scheduler production or consumption. Before any such
mutation, the fixture binds original allocator geometry: 213 raw words,
213 packed pointer slots,213 map words,82 queue entries and82 records, with
the following native region exactly after the records. Packed pointer access
uses byte copies. Scalar cache, queue, records, pointee contents, modes and
temporary descriptor fields are snapshotted and restored with byte readback.

The canonical native domains use separate fresh original factories:

- 644 ordinary calls cover all 92 public IDs with valid quantized values.
  Selected raw/pointee storage and queue/special/mode fields compare. Real
  callbacks also produced 55 per-call change observations outside the selected
  raw/pointee storage. Unique affected IDs were not measured; those effects
  are excluded and not restored. The original instance is destroyed normally.
- 354 controlled queue calls cover 59 real public type 1 specials and compare
  the complete prepared scalar snapshot, without substituted callbacks.
- 26,006 synthetic calls cover queue membership, stale motion, force/depth/
  immediate modes, dirty, clipping, cyclic flags and low-byte types in actual
  factory storage. Controlled scalar bytes restore before original destruction.

The canonical source fixture passes 33 successes and 6,019 atomic rejections;
native comparisons cover 11,287,672 words. Independent root and effects
reviews accepted the private bounded contract. Their additional native
half/adjacent-ULP/zero/queue tests and a wrong queued-gain negative control are
bound in the verification record. The public path recipe changes only source
documentation names and its ignored output directory.

These scalar snapshots do not capture whole native class state. Native unit
effects and callback execution, queue scheduling, factory/class ABI, preset
state, DSP/audio, GUI, VST/AU integration, real-time behavior and full-plugin
equivalence remain unproved. Ordinary native lifecycle/diagnostics can write
log, preferences and MIDI caches. No original machine code, assets or presets
are included in this source.
