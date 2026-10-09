# VL Soft Clipper native bridge and editor

This independently written C++ factory wraps the accepted numerical C API in
`soft_clipper_plugin.h`. The intact, identity-checked arm64 FLEngine DLL loader
accepts the compiled module. Its real host and plugin adapter classes exercise
our factory, callbacks, state streams and optional independently written AppKit
editor. This is a bounded partial reconstruction. Original VCL/artwork/GUI
behavior, complete source dispatch/event/name/metadata equivalence, actual FL
application/project/mixer lifecycle, x86/VST/AU and whole-plugin equivalence
remain unverified. No commercial target binaries or resources are distributed.

Run the maintained native checks on the pinned macOS arm64 installation:

```sh
./reconstruction/plugins/effects/verify_soft_clipper_engine_loader.sh
./reconstruction/plugins/effects/verify_soft_clipper_engine_stream.sh
./reconstruction/plugins/effects/verify_soft_clipper_editor.sh
```

The separate original-factory numerical comparison remains:

```sh
./reconstruction/plugins/effects/verify_soft_clipper.sh
```

The native and numerical verification JSON files bind their own sources,
compiler settings, target identities and independent review scope. The native
scripts use separate output directories; they do not overwrite another effect
family or the retained private candidate artifacts. All eight promoted
runtime/header/test files are byte-identical to the independently accepted
private candidate. Only script names, source input paths and output directory
names changed during promotion.

## Measured behavior and scope

| Original source function | Retained proof | Reconstruction limit |
| --- | --- | --- |
| Factory `0x6b90` / `0x5d4c0`, constructor `0x5dab0` | Real commercial factory creates/destroys; controls/defaults measured. Own C++ factory accepted by actual engine DLL loader and adapter. | Own class/lifecycle and metadata, without original Pascal/VCL constructor equivalence or application hosting. |
| Parameter `0x5dda0` | Numerical raw/normalized values, priorities, rounding ties and original control ranges/defaults compared in the numerical corpus. | Own numerical callback plus own editor automation refresh; remaining source UI flag/event timing unverified. |
| Render `0x5e2b0`, knee kernel `0x14e0f0` | Compiled numerical C API compared with original callback, pinned DSP dependency and synthetic meter states. | Finite supported input/frames/compiler domain in the C header; no unrestricted FP or realtime certificate. |
| State `0x5d9d0` | Source transfers eight bytes once, without version header. Real engine TMemoryStream/TStreamAdapter read/write own native state. | Own atomic validation and signed HRESULT32/completion32 handling; original malformed-state equivalence and full application state lifecycle unverified. |
| Dispatcher `0x5d540` | Original resume/rate numerical fields unchanged; classifications `52/0=1`, `52/1=5` measured. Own attach/detach, resize and Idle use actual engine host/plugin bridge. | Independently written editor behavior and selected dispatch only; remaining source cases unverified. |
| Destroy `0x5dd60`, names `0x5e190` | Source factory cleanup exercised; own native destruction and names exercised through engine adapter. | Own labels/cleanup and main-thread ownership; original VCL/artwork/resources and complete names/events parity unverified. |

The default build exposes our no-editor C++ factory. Defining
`VL_SOFT_CLIPPER_APPKIT_EDITOR` adds the editor flag and independently written
490-by-250-point AppKit view with two controls and pre-postgain knee peak
indicators. It uses the accepted raw ranges and numerical meter behavior,
including the full-eight-frame absolute-value peak groups and signed tail.
Refresh reads parameters/meters and clears the own numerical meter under the
host mix lock. Changes take that lock around the numerical setter, then deliver
host change/hint notifications after unlock. Idle refreshes and delivers a
pending resize after the actual engine wrapper has bridged the view handle.
This does not establish original GUI timers, reset cadence, display text,
artwork or layout equivalence.

Attach/detach updates meter enable under the paired host mix lock. Editor
creation/refresh acquire their own locks, so callers must not hold an outer
nonrecursive host mix lock around dispatch or Idle. The corrected canonical
fixture renders with the host mix mutex while 128 detach/reattach cycles check
exactly one lock around each meter-enable update: 256 dispatch lock cases.
Independent critique intercepted two unlocked writes before this repair and
zero after it; the retained pre-fix dylib fails the new actual-adapter fixture.

All numerical getter/parameter/state/render/destruction access must be
serialized or protected by the host mix lock. Hints with flag 4 are main-thread
GUI operations outside that lock, with numerical access otherwise serialized.
Tick and MIDI tick are independent no-ops. Worker hint/get access skips the
GUI-owned editor pointer before reading it; worker GUI dispatch, Idle and
refresh are skipped. Every optional-build native destruction requires main,
even before first editor attachment. A refused worker destruction preserves
ownership for main-thread retry; keep the host, plugin and module alive until
that retry finishes. Stop/serialize rendering before destruction. These
contracts do not claim unrestricted concurrent native access or realtime safety.

Caller audio/name buffers and stream interfaces must be valid external storage
outside both the factory and numerical objects. Name buffers need capacity for
at least ten bytes. The numerical C API independently rejects ranges that
overlap its own live object; the native C++ boundary does not validate arbitrary
host addresses. Native stream callbacks return signed 32-bit HRESULT values,
take 32-bit lengths and write 32-bit completion counts. The own restore checks
success and the complete eight-byte count before atomically applying state.

## Maintained checks

The DLL-loader fixture exercises all twenty callback slots, 2,400 parameter
calls, 1,200 state saves, 240 restores, failed-read preservation and 140,700
stereo frames through actual engine wrappers. It instantiates no FL application
host. The real-stream fixture uses actual TMemoryStream and TStreamAdapter
classes through the plugin wrapper: 128 saves/restores, a single eight-byte
transfer, preserved high-word count sentinels, measured invalid-pointer errors,
signed HRESULT32/full-count rejection and success/short-count rejection.

The standalone editor fixture covers 288 automation displays, two control
changes, meter full-group/signed-tail behavior, paired locks and notifications
after unlock, and worker UI/destruction refusal. The native editor fixture uses
actual engine host/plugin adapters for controls, hints, resizing, numerical
rendering, meters, detach/reattach and worker boundaries. It checks first editor
creation concurrently with serialized worker hints/getters, and attachment
meter updates during rendering under the shared host mix mutex. The maintained
paths receive a separate independent rebuild/replay before publication.

All fixed-offset harnesses refuse compilation outside Apple arm64 and verify
the intact universal engine SHA-256 before native calls. The engine universal
and extracted arm64 identities are recorded in the manifest; the installed
version must match before reusing offsets. Numerical math retains nearest-even
rounding, macOS arm64 26.6.2 build 25G83, Apple clang 21.0.0
(clang-2100.3.34.2), system libm and flags
`-std=c++20 -O2 -ffp-contract=off -fno-fast-math -fno-builtin-exp`.
