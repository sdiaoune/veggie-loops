# C++ Fruity generator factory subset

This is an independently written C++ Fruity factory route around the published
bounded multimode channel. It exports CreatePlugInstance and omits the original
Pascal selector SetExternalAppHandle. The intact FLEngine DLL loader selects its
C++ host and plugin adapters and copies the measured 168-byte public prefix.
This does not reproduce the original Pascal object, GUI, metadata flags, names,
all dispatch/event behavior, or all advertised processing callbacks.
The GetName/name stub requires a caller-owned writable buffer of at least 256
bytes. Its independently chosen labels do not establish original GUI/name parity.

The metadata declares 114 controls and full-generator/new-voice/tick flags only;
raw VoiceRender, effect, editor/MIDI/output-voice behavior are unsupported stubs.
All successful tested control, trigger, ordinary release, kill, max-poly,
tick, song-position, state and GenRender calls cross the original plugin adapter.
ComputeLR and completion callbacks cross the original host adapter to controlled
callbacks. Independent legacy tables are generated from reviewed source; no SDK
host table/data field is read. Actual host table delivery remains open.

A separate storage-only core keeps the controls and version14/456-byte payload
in sync; it creates no raw voices and calls a local scalar gain function only.
Factory creation consequently makes no original application host callbacks.
The actual DLL-loader test verifies metadata, 114 controls and 460-byte framing
with no channel/notes created. Its underlying application host is absent.
The state stream convention is strict HRESULT32 success=0, uint32 requested
lengths and uint32 completed counts; reads require exact 4/456 completions.
Other provider conventions and failed-save transaction atomicity are unproved.
The 460-byte comparison excludes bytes93..95, the three undefined payload
padding bytes at offsets89..91; the remaining457 bytes are compared.
The actual loader's host-adapter lifetime is not asserted or reconstructed.

The audio comparison uses 180 original factories and 180 rebuilt factories,
explicitly prepared fixed rate/tempo/PPQ contexts and independently generated
six-table banks. It compares every defined state output byte (version4 plus
453 defined payload bytes), excluding the original three undefined padding
bytes. The native adapter carries opaque plugin-owned voice handles and the
same caller-owned 40-byte writable parameters, which must outlive each voice.
Frames and scalar/control/callback/lifetime/serial/FP domains follow the
published multimode header. Nearest-even, gradual underflow and strict separate
float operations are required. All raw-engine instances and factory operations
must be serialized. Packed metadata is const after one-time guarded runtime
initialization, which avoids unaligned pointer relocation entries. No RT,
reentrant mutations, failed-allocation atomicity, arbitrary pointer or invalid
original-native-call certificate is given. Host callbacks are nonthrowing and
must defer note/list mutations until render returns. The original concrete
VoiceKill path separately measured in engine-generator-protocol-evidence.json
marks engine voice fields without a synchronous plugin kill in that path;
actual application-owned voices and later cleanup/scheduler remain unproved.

The successful ordinary note/render path runs through real adapter methods.
Explicit quick release still uses the previously accepted channel helper,
matching the original private editor helper. Rejection/invalid-time tests also
remain component calls and do not establish invalid native factory behavior.
Prepared context changes are supported only with no voices and reset channel
context. Live sample-rate/tempo/PPQ transitions are excluded. Automatic real
host clock production is excluded; seek uses a controlled 16-byte time callback.

The root independently accepted this bounded C++ factory subset after copied
normal and ASan/UBSan/float-cast-overflow replays. Both modes passed the
original-factory comparison and the intact-loader check: four checks in total.
The independent source-only sanitizer fixture also passed with an eight-byte
C++ host interface, two full-width voice tags, ordered nondeleting completion
callbacks, no factory-creation host callback and preserved live channel state
after rejected context changes. Swapping release/kill function entries 10/11
failed the real-adapter comparison with differing voice counts. These tests
cover the prepared contracts here, rather than an original application session.
The review record is root-three-osc-native-factory-independent.json; the
verification manifest preserves its prior tested hashes and the accepted
comments-only 256-byte name-buffer clarification.
Original Pascal/native class parity, application host ownership, clocks/tables,
custom/noise/random-phase and raw-mode integration beyond the existing corpus,
VoiceEvent/Flush and full dispatcher/name/GUI/state-version coverage are open.
Whole-plugin reconstruction/recompilation remains false.

Run ./reconstruction/plugins/generators/verify-three-osc-native-factory.sh,
optionally --sanitize, on macOS arm64 with the pinned installed targets. Outputs
are written under .tools/plugin-work/generators/native-factory-maintained.
The header, numerical callbacks and two native harnesses retain their accepted
implementations. The factory now uses the separately reviewed own lifetime split:
complete callback20 cleans the instance while retaining raw storage; callbacks0
and21 clean and free it. The first twenty table expressions remain unchanged;
callback0's body changes intentionally. Nine source profiles and twelve fatal
semantic negatives cover the three experimental oscillator factories. Normal and
fatal builds of this maintained original-driven factory/loader recipe also pass
with the repair. These tests do not certify original extra-destructor semantics.
See [own factory lifetimes](lifetime/README.md). Recipes explicitly build arm64
and strictly verify signed products before use. Only independently compiled source
and harnesses are instrumented; installed code is unmodified.
