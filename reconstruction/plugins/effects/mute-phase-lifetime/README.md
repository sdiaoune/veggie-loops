# Mute 2 / Phase Inverter source lifetime repair

The experimental native factories distinguish complete destruction from deleting
destruction. Complete destruction releases the numerical instance and editor,
ends the C++ instance lifetime, and retains its raw allocation. The caller then
performs matching raw deallocation only. Ordinary `DestroyObject` and callback
21 perform cleanup and free the allocation once. Callback 20 retains it.

Optional editors refuse all three routes off the main thread, including before
attachment. Keep the instance, borrowed host, wrapper and module alive until a
serialized main-thread retry. Successful editor cleanup clears callbacks/context
and control targets before releasing the view. A separately retained view is
inert while its class module remains loaded. Instance access requires serialization
or the host's mix lock.

Run on macOS arm64 with Xcode command-line tools:

```sh
python3 reconstruction/plugins/effects/mute-phase-lifetime/verify.py --phase source
python3 reconstruction/plugins/effects/mute-phase-lifetime/verify.py --phase native
```

The source phase runs 12 normal, fatal ASan/UBSan/float-cast-overflow and O0
profiles, plus 10 semantic negatives. It checks allocation failures, all three
cleanup routes, live peers, worker refusals and retained view actions. Allocation
hooks exist only in the fixture. Semantic negatives reject before an invalid
access; allocation counters cover the watched own allocations and LSan is off.

The native phase requires the pinned installed FL Studio 2024 engine. It runs
10 normal/fatal loader, editor and Phase stream outputs against unmodified
engine code. Each loader exercises 20 callbacks, 1,200 saves, 240 restores and
140,700 stereo frames. Phase uses actual engine streams for 128 saves/restores
and failed-HRESULT preservation. This group adds no new Mute real-stream proof.
Every own native product is ad-hoc signed and strictly verified before use.

Two independent runtime critics accepted this bounded repair; one added a
borrowed-host supplement. The public wrapper verifies hashes and copies inputs
into a fresh ignored workspace before running the unchanged reviewed recipe.
Use `--check-only` for source hashes without compilation. Python optimization is
refused at the public entrypoint. No binaries, commercial resources or decompiled
source are included.

Original extra-destructor ABI, caption/events, commercial GUI, application,
project/mixer integration, x86/VST/AU and real-time behavior remain unproved.
Whole-plugin equivalence is false.
