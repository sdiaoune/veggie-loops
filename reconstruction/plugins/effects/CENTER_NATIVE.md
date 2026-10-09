# VL Center native bridge

This independently written, no-editor C++ factory wraps the bounded numerical
API documented in `CENTER.md`. The pinned intact arm64 FLEngine DLL loader
accepts its `CreatePlugInstance` export and allocates the real plugin wrapper.
The real engine memory-stream and COM adapter classes also save and restore its
state. This is a measured alternate factory bridge, not a reconstruction of the
original Pascal/VCL class or a complete plugin-equivalence certificate.

```sh
./reconstruction/plugins/effects/verify_center_engine_loader.sh
./reconstruction/plugins/effects/verify_center_engine_stream.sh
```

Both fixtures require the pinned installed FLEngine, refuse compilation outside
Apple arm64 and verify its universal SHA-256 before using measured offsets.
They load the intact library read-only; neither creates an actual FL Studio
application host. The runtime, header and two native fixtures are byte-identical
to the independently accepted private candidate. Scripts change only maintained
source/name/output paths. `center-native-verification.json` binds those files,
their numerical/shared-header dependencies and the separately reviewed scope.

## Factory and callbacks

The own factory uses the measured 168-byte C++ protocol header and twenty
forwarding callbacks. Its numerical pointer immediately follows that header,
with offsets asserted in source. The plugin info has stable module lifetime and
uses the own names `VL Center`; metadata/name equivalence to the commercial
plugin is unproved. Dispatcher resume 2 clears numerical history, rate 4 accepts
integer 8,000..384,000 Hz while preserving history, and classification 52 returns
the measured zero result. Parameter, render and valid state work delegate to
the accepted numerical C API. Unused effect voice/tick/message callbacks are
explicit independent no-ops; equivalent behavior for every original base-class
event, name or dispatch path has not been established.

The intact loader fixture exercises all twenty forwarding callbacks, 1,200
parameter calls, 1,200 saves, 240 restores and 140,700 stereo frames, then
destroys the numerical instance through `DestroyObject` and frees the real
engine wrapper. The two additional complete/deleting C++ destructor table
entries are present but have not been separately replayed. These checks do not
certify the complete C++ destructor ABI.

## State streams

State remains eight little-endian bytes: version 1 on save and raw enable 0/1.
The native callback performs two four-byte transfers. Restore accepts valid
versions 0/1 and commits only after both reads return successful signed 32-bit
HRESULTs and exact completed counts. Length and completed-count stores are
32 bits. The local count storage is zeroed before each transfer; high-word
sentinels in the provider fixture verify that the actual provider writes only
the lower word. Restoring enable preserves sample-rate coefficients and all
four retained double history fields.

The real-stream fixture performs 128 saves and 128 restores through the actual
TMemoryStream/TStreamAdapter and plugin-wrapper classes. It checks the invalid
pointer provider error, two-four-byte framing, count sentinels, and both first-
and second-read failures. A full completion count with failed HRESULT and a
successful HRESULT with a short count each reject atomically, preserving enable
and primed nonzero history. General arbitrary-provider behavior remains open.

The save callback returns void and issues the two writes without propagating
failed-write status. Only valid write framing has been replayed. Failed-write
rollback, general failed-write parity and complete application stream lifecycle
are unproved; restore error checks do not establish those properties.

## Caller contracts and remaining gates

Every numerical/getter/state/render/destruction access must be serialized or
protected by the host mix lock. Caller audio, name and stream storage must be
valid and external to the live factory and numerical objects. Name output
capacity is at least eight bytes. Host addresses are caller-provided protocol
objects, not validated opaque handles. The numerical finite-input, frame, rate,
aliasing and FP-environment limits in `CENTER.md` still apply. There is no
unrestricted concurrency or realtime certificate.

An own optional editor requires separate source and review. Original VCL,
resources and hint timing; original metadata/name/event/remaining dispatch
semantics; actual FL application/project/mixer lifecycle; x86, VST and AU
hosting; general provider and failed-write behavior; complete destructor ABI;
and whole-plugin equivalence remain open. Distributed source contains no
commercial binaries, resources, SDK headers or raw decompiler output.
