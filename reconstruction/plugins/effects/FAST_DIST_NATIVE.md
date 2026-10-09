# VL Fast Dist native bridge

This independently written no-editor C++ factory is accepted by the pinned intact FLEngine DLL loader and callback adapter. It reconstructs that bounded loading/control/state/render boundary; it does not establish original Pascal class or complete application/plugin equivalence.

The common Balance native header supplies protocol declarations. Numerical control/input/frame/alias/FP limits are those in `fast_dist_plugin.h`. All instance access, including getters, state, render and destruction, must be serialized or protected by the host mix lock. Host, plugin and modules must remain alive while calls are in flight. Own parameter names require writable caller capacity of at least 10 bytes. Metadata, names and unused callback no-ops are independently chosen behavior, separate from original base/UI semantics.

The factory creates the numerical engine with integer quality 0. It does not inspect or reconstruct actual original host branch/quality transitions. The separately verified numerical API can select quality 0/1, but this bridge's factory default is explicit. No Fast Dist editor is included here.

The intact loader adds `_X64` to the logical plugin path and selects the C++ protocol because `SetExternalAppHandle` is absent. It allocates the original C++ to Pascal wrapper around the rebuilt object. The fixture exercises 20 callback slots, defaults, five classifications, parameters, state, exact-alias/disjoint render and teardown. Two additional C++ destructor entries exist in the declaration; separate replay of those entries remains open.

State uses one 20-byte transfer. The measured real `TMemoryStream`/`TStreamAdapter` provider returns signed 32-bit HRESULT, accepts 32-bit length and writes a 32-bit completed count. The fixture verifies adjacent count sentinels, the actual invalid-pointer HRESULT and 128 save/restore roundtrips. Synthetic full-count failed HRESULT and success/short-count reads reject atomically, preserving parameters and derived coefficients. Wide zeroed local completion storage also accommodates the retained synthetic provider fixture. Save has a void return; general failed-write handling/provider equivalence is not proved.

```sh
sh reconstruction/plugins/effects/verify_fast_dist_engine_loader.sh
sh reconstruction/plugins/effects/verify_fast_dist_engine_stream.sh
```

Both identity-bound fixed-offset fixtures refuse architectures other than macOS arm64 and verify the engine universal SHA before loads/calls. Build flags match the numerical source. The loader passes 20 slots, 6,000 control calls, 1,200 saves / 240 restores and 140,700 stereo frames. The stream fixture passes 128 roundtrips and both failure classes. Neither creates the FL application.

Two independent native reviews reproduce both canonical scripts. Root's source-only sanitizer fixture adds 40 signed-HRESULT/count combinations and five malformed packets; three valid combinations accept and 37 preserve state atomically. Its intptr_t HRESULT mutant fails the real stream fixture. Generator review adds 45 exact 10-byte name canaries, 30 full-width dispatcher cases, three unused callback guards, two simultaneous actual-adapter instances plus teardown/recreation, all defaults, numerical quality discrimination and restore-quality preservation. These additional private review probes are distinguished from maintained canonical test counts.

A two-line native-header clarification points explicitly to Fast Dist numerical contracts; runtime, declarations and fixtures are unchanged from accepted private source. Its prior header bytes/hash are retained in the ignored analysis evidence. The maintained-path manifest binds the promoted source and records final root rebind separately.

Original Pascal/base/VCL/editor equivalence, remaining events/dispatch/metadata/name semantics, original host branch configuration and production, actual FL application/project/mixer/stream ownership lifecycle, general provider/write failures, extra destructor entries, x86/VST/AU and realtime/full-plugin equivalence remain open. No original binaries, SDK code or assets are redistributed.
