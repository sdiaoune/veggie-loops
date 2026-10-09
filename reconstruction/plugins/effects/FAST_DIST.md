# VL Fast Dist numerical reconstruction

This independently written C API rebuilds a bounded numerical portion of Fruity Fast Dist. It does not establish complete plugin equivalence. The source contains independently generated lookup tables and DSP code; original binaries, assets, captured source and SDK headers are not distributed.

The installed arm64 plugin creates a Pascal class with five raw controls and three coefficients. Its audio callback copies disjoint input and calls the host's `DistWave_32FM`. The actual distortion belongs to FLEngine. Bare engine loading leaves those lookup tables uninitialized; the comparison fixture calls the intact pure table initializer before comparing DSP. A typed synthetic factory host forwards audio to that intact host routine. It is a bounded fixture context, not a created FL application or reconstructed original host class.

The source independently regenerates all 20 rows of 8,194 signed 16-bit entries, including guards. All 163,880 entries match the initialized engine. Both integer and interpolated host kernels are rebuilt. The fixture explicitly selects engine branch byte 0/1 inside its own process and restores its prior value. This tests numerical branches; original application transitions are not wired into the rebuilt factory. Static usage binds the observed “HQ for all plugins” label to bit1 of a separate object field in two setting-related functions. Its relationship to the global branch selector and its persistence lifecycle remain unproved.

| Index | Own label | Raw domain | Default |
| --- | --- | --- | --- |
| 0 | Pre Gain | 64..192 | 128 |
| 1 | Threshold | 1..10 | 10 |
| 2 | Type | 0..1 | 0 |
| 3 | Mix | 0..128 | 128 |
| 4 | Post Gain | 0..128 | 128 |

The verified normalization range is 0..2^30 with nearest-even rounding. Flags 0/1/2/3/32/33/34/35 are supported, with set taking priority. Raw getters ignore their input value. Presets are exactly 20 little-endian bytes containing five raw int32 values without a version field; restore recomputes coefficients and preserves the selected numerical quality.

Use the domains in `fast_dist_plugin.h`: all access to an instance, including getters, save and destruction, must be serialized or protected by the host mix lock. Rendering accepts finite stereo floats with absolute input at most 16, 0..1024 frames and exact alias or disjoint buffers. Partial overlaps and any caller buffer overlapping live instance storage reject atomically. Caller storage must otherwise be valid. These invalid-input checks extend the new C API; malformed original-call equivalence is not claimed. No render allocations occur. Tables initialize on first creation under the caller's default nearest-even FP environment.

```sh
sh reconstruction/plugins/effects/verify_fast_dist.sh
```

The original comparison requires the pinned installed macOS arm64 binaries and Apple clang. It refuses a changed universal engine/plugin identity and verifies the mapped DSP copy dependency before native calls. The build uses `-ffp-contract=off -fno-fast-math -fno-builtin-exp -fno-builtin-log`; the tested environment is recorded in the manifest. The source-only ASan/UBSan boundary fixture loads no original binaries.

Author replay passes 44,879 parameter/control cases, 4,800 callbacks / 562,800 stereo frames, 256 valid saves / 256 restores, all table entries, source immutability and independent guard checks. The source-only boundary fixture passes 502 atomic rejections and eight nullable zero-frame cases. Independent numerical critique reproduces those cases and adds 4,800 edge cases / 1,075,200 exact output floats across all rows and both qualities, normalized ties/flag priority and aliases. Its deliberate wrong-quality shim fails the actual factory comparison; the unchanged source passes.

Original Pascal factory/base/editor/resource semantics, remaining control and host flags, names/hints, actual application/project/mixer lifecycle, general original state-provider errors, x86/VST/AU and realtime/full-plugin equivalence remain unproved. The separate no-editor native bridge is described in `FAST_DIST_NATIVE.md`.
