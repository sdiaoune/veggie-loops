# Center lifetime and engine replay

This package verifies the independently written Center factory's bounded C++
lifetime behavior and regression compatibility with measured intact FL engine
adapters. It does not certify the original Center class or the full plugin.

The own factory complete destructor (slot 20) cleans resources and ends the
Instance lifetime while retaining raw storage. Ordinary DestroyObject (slot 0)
and deleting destructor (slot 21) also free that storage exactly once. After
successful complete cleanup, only matching raw storage deallocation is valid;
getters or another destructor must not be called. All three optional editor
routes refuse off-main before touching instance/view/numerical state, including
before attachment. Preserve object, host and module until main-thread retry.
Calls remain serialized under the existing numerical/host contracts.

From a published source tree, binding checks require neither FL Studio nor a
compiler and create no work files:

```sh
python3 reconstruction/plugins/effects/center-lifetime/verify.py --check-only
```

With an explicit serial compiler/native lease, the default replays source first,
then native checks. Source-only replay does not read installed original files.
Native/all requires the exact installed arm64-capable engine hash recorded in the
manifest and macOS arm64. Native fixtures do not create the FL application.

```sh
VL_CENTER_PUBLIC_SLOT_GRANTED=1 python3 reconstruction/plugins/effects/center-lifetime/verify.py
VL_CENTER_PUBLIC_SLOT_GRANTED=1 python3 reconstruction/plugins/effects/center-lifetime/verify.py --phase source
VL_CENTER_PUBLIC_SLOT_GRANTED=1 python3 reconstruction/plugins/effects/center-lifetime/verify.py --phase native
```

Every run stages fresh exact public copies and generates its candidate map under
ignored `.tools/plugin-work/effects/center-lifetime-public/replay-*`. Prior private
analysis, failures, original-source captures and Git history are not inputs.
The canonical recipe and source/native fixtures retain their accepted bodies;
the recipe adds only an early copied-workspace guard. Invoke the public wrapper,
not that lower recipe directly. The canonical recipe's failure path lacks a full
finally audit; the outer wrapper supplies it. Expected copy/map/registry bindings
are registered before attempted directory/copy/write operations. Finally attempts
all public, manifest, copied, generated and applicable engine identities even on
failure, preserving primary and postflight errors separately. No outer pass is
reported before final audit. An incomplete write or audit is a failure; raw
canonical logs/products, including partial results, are evidence, not a pass.
The final result write is protected, including a full write followed by an
error. Its error is recorded separately in postflight, which is saved after
that attempt. Success requires the completed wrapper command, its stdout and
clean postflight; a result file alone cannot certify a run. If postflight
cannot be saved, the command still rejects and includes the recording error.

Expected source coverage is nine profiles (plain, optional default and optional
editor at O2, fatal O2 and O0), four fatal semantic negatives, and thirteen signed
strict arm64 products. The source fixture supplies a null borrowed host, creates
its own NSApplication, tests own allocation hooks/two-instance peer preservation
and retained AppKit view actions, and does not load original images. The unchanged
production modules have no test cleanup spy.

Expected native coverage is ten exact typed result documents and sixteen signed
strict arm64 products, using plain/optional-default loader and actual stream
fixtures plus optional-editor adapters at normal/fatal O2. Loader exercises the
ordinary twenty callbacks; original extra destructor slots 20/21 are excluded.
The native editor's 128 concurrent render/reattach cycles per mode run with
centering bypassed. That corpus does not prove enabled-history concurrency.
Own source/harness are instrumented in fatal modes; installed engine and system
Cocoa remain plain. Deliberate semantic leak mutants use disabled LSan plus
mandatory selected own allocation counters; memory/UB/float-cast diagnostics
remain fatal. Every executable/module is signed and strictly verified before use.

Names, events, DSP, coefficients and state callbacks are unchanged by the lifetime
repair. Original names/events, extra destructors, allocator/class behavior,
commercial GUI parity, FL application scheduling, real-time operation and whole
plugin recompilation remain unverified. Independent scoped proofs are cited as
literal hashes in the manifest; no captured commercial assets are included.

Replay status is recorded in `verification.json`. The accepted private proofs
remain separate from the public-package replay.
