# VL Fast Dist optional editor

This independently written AppKit view provides four sliders, a Curve B
checkbox and five integer readouts for the bounded Fast Dist numerical API.
It uses the real engine host/plugin adapters for changes, hints, editor-handle
publication and deferred resize notification. It does not reproduce the
original VCL editor, artwork or full application behavior.

```sh
./reconstruction/plugins/effects/verify_fast_dist_editor.sh
```

`fast_dist_native_editor_candidate.cpp` is a separate optional factory wrapper.
Define `VL_FAST_DIST_APPKIT_EDITOR` and link `fast_dist_editor.mm` with ARC and
Cocoa to enable the view. Compile the same wrapper without that macro for the
measured default no-editor behavior. Six runtime/header/fixture files are
byte-identical to the independently accepted private candidate. The script
changes its name, source inputs and ignored output directory. The sixteen
published numerical/default-native files remain unchanged.

## Controls, locking and ownership

The controls retain the five measured raw domains: pre gain 64..192, threshold
1..10, type 0/1, mix 0..128 and post gain 0..128. The threshold slider has ten
ticks; the checkbox selects raw type 1. A refresh reads all five raw values
within one paired host mix lock, then updates AppKit controls after unlocking.
UI changes write the numerical parameter under the lock. Change and hint
callbacks follow unlock. Refresh preserves raw values, all three derived
coefficients and the caller-selected processing quality. Quality selection is
outside this editor. New labels and hints are independently written; original
hint contents and timing remain unproved.

Every GUI operation and every optional-build native destruction requires the
main thread, including destruction before attachment. Worker Idle, attach,
detach and hint calls return before reading GUI-owned fields; tick and MIDI
tick are no-ops. An off-main standalone destruction returns zero without
releasing the view. Native `DestroyObject` has a void result and refuses
release off-main, preserving native/numerical/view ownership for main retry.
Callers must retain the original engine wrapper, numerical instance, host,
context and modules through a successful main-thread retry. They must not free
the engine wrapper or unload a module following a refused destruction.

All numerical, getter, state, render and destruction access remains serialized
or protected by the host mix lock. The optional bridge requires valid paired
host CPP slots 32/33. Main-thread native parameter calls requesting a hint
(flags bit 4) occur outside the caller's mix lock; they internally lock their
numerical get/set work and notify after unlocking. Holding a nonrecursive mix
lock around such a main hint call would deadlock. Worker numerical calls
retain caller serialization and skip GUI work. External storage and host
lifetimes remain caller contracts. The numerical/control/input/frame/alias/FP
limits in `FAST_DIST.md` and name/stream/provider/destructor limits in
`FAST_DIST_NATIVE.md` continue to apply.

## Verification scope

The maintained script runs standalone editor, actual engine host/plugin
editor adapters, same-wrapper default intact loader and same-wrapper default
real-stream checks. Standalone coverage exercises 399 automation displays and
399 raw control actions, preserving parameters and coefficients. Two
processing-quality probes produce different audio and preserve the selected
quality through refresh.

The actual-adapter fixture repeats all 399 raw actions, checks automation,
32 refresh/quality cases and 32 optional native state saves/restores. It covers
concurrent first attachment with worker hint/get calls, worker tick/Idle/detach
refusal, deferred resize and off-main destruction before/after attachment.
It also runs 128 enabled, nonidentity render/reattachment cycles using integer
quality 0, plus 128 main-thread hint/set lock cases. Every native eight-frame
worker block is compared bitwise with a separate worker-owned C API instance
initialized from the same twenty-byte state snapshot under the mix lock.

Independent critique separately ran 256 enabled interpolated-quality-1 cycles
with randomized finite stereo input and an independent per-block numerical
reference. Twenty malformed optional-editor state packets preserved raw bytes,
coefficient bits, selected quality and output. Its own module and fixture passed
ThreadSanitizer with fatal diagnostics enabled. Original FLEngine was not
instrumented. Removing the main hint numerical lock in a reviewer-owned mutant
fails the expected lock assertion. These extra critic checks are separate from
the maintained author fixture counters and provide no general race or realtime
certificate. The independently reviewed offscreen bitmap is readable.

The default-wrapper regressions retain twenty callbacks, 6,000 parameter calls,
1,200 saves/240 restores and 140,700 frames through the intact engine loader.
The real stream checks retain 128 saves/restores, signed 32-bit HRESULTs,
32-bit completed counts and atomic full-count-error/short-count rejection for
the single twenty-byte state transfer. Numerical default quality remains 0.
Native fixtures refuse compilation outside Apple arm64 and pin the universal
engine hash before calling measured offsets.

Actual FL application/project/mixer hosting, original VCL/artwork/GUI/hint and
remaining host semantics, original host quality production, two extra C++
destructor entries, general failed-write/provider/reentrancy behavior, x86,
VST/AU, arbitrary environments and unsynchronized/realtime concurrency, and
whole-plugin equivalence remain open. Exact source/dependency/review bindings
and the maintained-path publication gate are in
`fast-dist-editor-verification.json`.
