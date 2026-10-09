# TyrellN6 prepared no-XY queue consumer

This independent C primitive reconstructs one scalar invocation of original
callback 0x153da0: remaining-count progression, raw current values, queue removal,
visited-ID bookkeeping and bit copies to scalar pointee words. It is a prepared
storage API, not the native C++ class, a scheduler or a DSP/audio implementation.
Nonzero XY counts reject atomically. The header defines finite bounds and all
storage/lifetime/alias requirements. Equal pointee indexes explicitly model
native pointer aliasing; the source never dereferences foreign pointers.

The pinned installed universal SHA is
`a825551500600e8c0194c285602cf58c2288b090de5e83da876ae3a7cc42ce54`.
Receiver VFT 0x120 getter 0x153d90 returns unchanged callback 0x153da0. The direct
fixture obtains that function from the actual factory getter. It builds the
same three-word context as the original render route, using actual config and
receiver fields. Consumer entry/exit calls the actual receiver's VFT 0x50 no-op;
no unit/VFT/function pointer is substituted. The VST host remains the controlled
reference host. Installed native code is uninstrumented.

Each visited queue record decrements once. Old remaining<=1 completes to -1,
copies target bits to raw and removes the entry by swapping the final active
slot without advancing the iteration index. Otherwise raw adds increment.
Flag 0x200 wraps once using maximum-minimum, with strict comparisons. This differs
from the notifier's maximum-based shorter-difference calculation. The consumer
writes ID-to-visit-position and visit-position-to-ID arrays, then copies raw
bits to actual pointees in reverse visitation order. A queue count of -1 becomes 0.
Dirty clears after a successful call. General floating exception/status/trap
parity remains unproved; nearest-even, gradual FP and separate operations apply.

Source state is fully initialized, bounded and serialized. Descriptors, state
and result must be disjoint. All count/range/index/overlap/unsupported-XY
checks and computed-current bounds reject without committing state or result.
Inactive array bytes remain unchanged. Records, raw and index arrays are scalar
copies; the fixed capacity 213 is an independent prepared API capacity. Native
factory proofs use its actual 213 internal IDs and 82 special records.

The direct native corpus uses one fresh original factory. It binds the actual
allocation geometry through the changed-ID array: 7152 bytes, with modulation
counts 0, actual packed pointer table and all original descriptors/maps. It
snapshots these configuration bytes, descriptor bytes and every unique original
four-byte pointee. Each controlled case restores all captured spans/words with
readback before proceeding; this does not capture every native class or unit
field. Temporary cyclic flags and pointer aliasing restore before destruction.
The only processing invoked while controlled is the unchanged consumer, with
actual no-op receiver entry/exit callbacks. No audio processing or unit setter
runs while those scalar fields/pointers are controlled.

Direct cases cover 59 public type 1 specials, remaining -1/0/1/2/50, signed-zero
increments, endpoints/adjacent ULPs and bounded out-of-range currents, synthetic
cyclic flags, empty/initial queues and three-record permutations. Swap-last
revisit and reverse-copy ordering compare through real aliased pointees. These
17,290 calls compare the complete prepared snapshot and have 17,290 captured
restoration readbacks. The temporary mathematical states and pointer aliases
are not asserted to be produced by an actual host scheduler.

A separate fresh original instance uses only its normal VST lifecycle, public
setters and replacing callback at 48000 Hz/64 frames. Its first render enables the
queue by changing -1 to 0. All 59 public float-special controls use normalized
.125/.875 targets, each followed by 56 renders. These 6,609 actual render calls
cover 422,976 frames and 118 exact target completions. The source step starts from
the actual pre-render scalar snapshot; setter/unit effects are not independently
reconstructed by this test. Full queue/raw/special/visited bookkeeping and
visited pointee bits compare. Original processing also changes some nonvisited
pointee words; these are counted by representative ID and explicitly excluded
from source parity. Ordinary class/unit state is not rolled back; this isolated
original instance is stopped and destroyed through its normal lifecycle.
The maintained fixture checks finite original rendering and unchanged output
boundary sentinels. A separate private reviewer extension verified 845,952 zero samples in
this no-MIDI corpus; the ordinary public replay does not repeat that extension. No new musical
audio effect or source audio comparison is claimed.

The maintained render run observed 6,614 changes outside visited pointee words:
representative ID 45 changed 6,609 times; IDs 18/47/48/49/50 changed once each.
These are per-call word-change observations, not every aliased logical ID or
complete unit effects. A later fresh committed checkout observed 6,618 such
changes, including four additional changes represented by ID 54. All in-scope
queue comparisons and negative controls still passed. These excluded counts
can differ between runs; their causes remain unfinished and no exhaustive
unit-effect parity is claimed. The earlier descriptor probe classifies ID 45 as type 4
and the other representatives as type 3. Their actual causes/effects are not
reconstructed by this scalar step; no timing or audio equivalence is inferred.

Run `sh reconstruction/plugins/external/tyrell/queue-consumer-verify.sh`.
An explicit output-directory argument remains supported. The default output is
ignored `.tools/plugin-work/external/tyrell/queue-consumer-public-check`, derived
from the project root; source directories receive no compiled artifacts.
The script builds a new dynamically linked Intel C library and native fixture,
plus source-only arm64/Intel contract fixtures, all with fatal ASan/UBSan/float
cast checks. Every owned Intel artifact is signed and verified before execution.
The source-only corpus includes full 213-capacity completion and invalid count,
XY, record/index, numeric and all-byte-overlap rejections; unsafe native invalid
inputs are never attempted. Four isolated source mutants change decrement,
reverse-copy order, cyclic range or revisit behavior; the unchanged native
fixture must reject each without any target-code/callback mutation.

The initial lifecycle/static mapping and earlier first builder artifacts/logs
are retained separately. Complete unit effects, active XY modulation, other
block sizes/rates or queue scheduling, application host/clock/ownership, whole
class/factory/state, GUI, real-time behavior and full-plugin equivalence remain
unproved. Original lifecycle/diagnostics can write ordinary logs, preferences
and MIDI caches. No original code, assets or presets are embedded. The bounded prepared scalar consumer was independently accepted by the parent
and generator reviewer. The original header/runtime/two fixtures are promoted
byte-identically; the recipe changes only source/document names and output/root
paths. The ordinary public recipe requires only these public source files, the
unchanged common `vst2_probe.mm`, normal compiler/runtime tools and the pinned
installed Tyrell bundle. It never reads ignored private mappings, failures or
review artifacts. Historical evidence is referenced by its frozen hashes in
queue-consumer-verification.json; those references are not replay inputs.


The frozen private candidate is
`a88a481de232c7352e1a9f26c7637749838a65261234d4083f31da9e6d75e6ae`.
The combined independent acceptance is
`b2ea0c946bdcc0f3c25ccb029212886fe1c4b98fca4915990738e6f3ae1d3188`.
The parent review is
`614b5f1234762358488ae51f3f80a02e10ef0520fdf6cf598f3a7fbc2e6d236b`;
the separate generator review is
`69bfb538fe4be6a115456907f7d6358ce0a7b429cfed77fea9247e4d1dc4ed6c`.
These reviews include additional private probes, including independent duplicate
queue/alias/zero-output checks. Their private extensions are distinct from the
maintained public corpus and are not claimed to execute during ordinary replay.
Native execution is restricted to macOS Intel; the recipe builds arm64 and
x86_64 source fixtures and runs the signed Intel original-target fixture on the
reviewed Apple Silicon/Rosetta environment. It does not install Rosetta or the
plugin. Original-target verification fails when the pinned bundle is absent or
changed. No target binaries, descriptor snapshots, machine code, presets or
assets are distributed with this source.
