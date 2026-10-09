# VL Center optional editor

This independently written AppKit view adds an enable checkbox and two retained
offset readouts to the bounded Center numerical API. The optional C++ factory
build uses the real engine host/plugin adapters for parameter changes, hints,
editor-handle publication and deferred resize notification. Original Pascal,
VCL, artwork and GUI-equivalence claims remain excluded.

```sh
./reconstruction/plugins/effects/verify_center_editor.sh
```

The separate `center_native_editor_candidate.cpp` wraps the published numerical
runtime. Define `VL_CENTER_APPKIT_EDITOR` and link `center_editor.mm` with ARC
and Cocoa to enable its view. Compiling that same wrapper without the macro
provides the measured no-editor behavior. The numerical implementation retains
its accepted body. The candidate suffix identifies this separate
wrapper's reviewed origin; it does not assert full application compatibility.
The current factory includes the separately accepted own lifetime repair;
editor control code and native fixture bodies retain their accepted versions.
Source hashes, dependencies, historical bindings and review scopes are bound
in `center-editor-verification.json`.

## Controls, locks and ownership

The checkbox writes raw enable 0/1 through the own C API. Refresh snapshots
enable and all four double history values within one paired host mix lock,
then displays the left/right positions to four decimal places. Refresh does not
clear or change history. UI writes also hold the mix lock and send change/hint
notifications after unlocking. Hints describe the own on/off control; original
hint contents and timing are unproved. Native parameter calls with the hint
flag still perform numerical work on workers but skip GUI state there.

All view operations and every optional-build native destruction require the
main thread, including destruction before first attachment. Off-main calls
return before reading GUI-owned editor/pending fields. The standalone destroy
returns zero off-main without releasing ownership. Native `DestroyObject` has a
void signature and refuses release off-main; callers must keep the native and
engine wrappers, numerical instance, host/context and module alive until a
successful main-thread retry. They must not free the engine wrapper or unload
the module after a refused call. Main destruction detaches the view before
freeing numerical state. Successful cleanup clears retained view callbacks,
context and control targets. Complete slot20 retains raw storage after ending
the Instance lifetime; DestroyObject0 and deleting slot21 free it. All routes,
including complete cleanup, refuse workers. Keep the object, numerical state,
host and module alive for main-thread retry, and never call getters or a second
destructor after successful complete cleanup.

Every numerical/getter/state/render/destruction access remains serialized or
protected by the host mix lock. The optional bridge requires valid paired host
CPP slots 32/33, mapped through the measured real host adapter to the Pascal
mix-lock methods. UI fields are owned by main; tick and MIDI tick are no-ops,
and worker Idle/attach/detach/hint calls skip UI access. Host lifetimes and
external storage are caller contracts, not validated arbitrary handles. The
finite-input/rate/frame/aliasing/FP limits in `CENTER.md` and the stream/name/
destructor/provider limits in `CENTER_NATIVE.md` continue to apply.

## Verification scope

The maintained script runs four checks: standalone editor, actual host/plugin
editor adapters, default-wrapper intact loader, and default-wrapper real-stream
regression. Standalone coverage includes 256 automation updates, 514 offset
display cases, 258 UI actions including bitmap setup, preserved history across
refresh/bypass and reset display. The actual-adapter fixture checks two UI
changes, 65 retained-position displays over four rates, bitwise native rendering
against an own reference, first-attachment worker hints and refused worker
destruction before/after attachment. It checks worker tick/Idle/detach refusal,
deferred resize and 128 concurrent render/reattachment cycles. Those author
concurrency cycles deliberately use bypass rendering, so they establish
lifecycle/serialization behavior with unchanged history.

Independent critique separately ran 128 concurrent reattachment/refresh cycles
with centering enabled, a fresh reset and 44.1 kHz. Every native eight-frame
worker block matched a worker-owned numerical reference bitwise. The same
enabled critic fixture passed ThreadSanitizer without diagnostics. That run
instrumented the new module and critic fixture; original FLEngine was not
instrumented. These added checks are separate from the maintained author
script's counters and do not provide a general concurrency or realtime
certificate. The offscreen bitmap was independently reviewed as readable.

The default-wrapper regressions retain the twenty-callback/140,700-frame loader
and 128-roundtrip real-provider proofs described in `CENTER_NATIVE.md`. The
native editor fixture refuses compilation outside Apple arm64 and validates
the pinned engine SHA before calling measured offsets. Actual FL application,
project and mixer hosting; original GUI/hint/metadata/remaining host semantics;
original extra C++ destructor slots; general failed-write/provider behavior; x86/VST/AU;
realtime/unsynchronized concurrency; and whole-plugin equivalence remain open.

The separate [own lifetime replay](center-lifetime/README.md) checks the repaired
three cleanup routes at normal/fatal O2 and O0, with retained view actions,
worker refusals, two-instance preservation and four deliberately wrong variants.
Its native regressions use the existing twenty callbacks and bypassed 128-cycle
editor fixture. Earlier enabled-history and ThreadSanitizer results retain their
historical source bindings; this repair does not relabel them as a new replay.
