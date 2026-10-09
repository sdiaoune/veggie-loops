# Prepared meter

This standalone C++20 package provides `vl::labs::prepared_meter`: caller-owned transfer-table construction, fused interpolation, sample history, held fast/slow levels, and activity-timer updates. It is independently written source over supplied storage. It does not load LABS, synthesize sound, or initialize an installed plugin's tables or globals.

The caller supplies live, aligned storage and serializes every access to the state, tables and outputs. `State` is this API's own 52-byte layout. State floats are finite with magnitude at most 1024 and nonnegative rates; elapsed time is finite in [0,64]. Samples are finite in [-2,2]. Lookup tables contain exactly 1000 finite values in [0,1]. Transfer thresholds contain exactly 100 ordered finite doubles in [0,1] and end at 1; repeated thresholds and both signs of zero are allowed. Tables need not be monotone. Defined table/output/state overlap is rejected where both objects are arguments. These are defensive new-API bounds, not measured native allocation or malformed-input contracts.

Interpolation uses `std::fma(fraction, distance, lower)`, and decay uses `std::fma(-rate, elapsed, level)`. When either level is positive, both channels advance. A positive hold timer consumes time without same-call residual decay; a nonpositive decayed result becomes positive zero. Build for IEEE binary32/binary64, nearest-even rounding, gradual underflow, masked traps, no fast-math or excess precision, and contraction disabled outside explicit `std::fma`. Full-table validation has no real-time performance certificate.

The library depends only on its header, source, standard C++20 library and math implementation. The supplied test additionally requires macOS arm64, reads FPCR without changing it, and refuses incompatible rounding/underflow/trap settings. The measured own-source environment was macOS arm64 Clang with FPCR 0 at O0 and O2. Other architectures, compilers and FP modes have not been validated.

In a fresh copy of this directory, the two positive profiles can be built, signed and checked with the platform tools:

```sh
mkdir build
for profile in O0 O2; do
  clang++ -arch arm64 -std=c++20 -"$profile" -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror prepared_meter.cpp test_prepared_meter_arm64.cpp -o "build/test-$profile" || exit 1
  codesign --force --sign - "build/test-$profile" || exit 1
  codesign --verify --strict "build/test-$profile" || exit 1
  "./build/test-$profile" || exit 1
done
```

The test contains 13 own-source checks: fused lookup and decay bit patterns, a separate-rounding decay witness, hold-without-residual behavior, a finite negative-to-positive-zero clamp, and eight signed-zero combinations with a positive peer. It checks reserved-byte preservation within those eight cases. Checks do not use `assert`. The result reports `own_source_checks_passed: 13`, the observed FPCR, `original_called: false`, and `full: false`. The separate witness gives fused `0x3f27aa4b` versus separately rounded `0x3f27aa4a`; the lookup witness expects `0x3e940ad7`.

Historical private verification compiled the mechanically equivalent own source at O0 and O2 and rejected five deliberate variants: unfused lookup, unfused decay, reversed decay sign, retained negative zero, and residual hold decay. This proposed namespace/file layout has not yet been compiled or run. `scope.json` records the historical claims, exact mutation anchors and pending package replay. No private evidence file is a build or runtime dependency.

Historical digests are source proposal `e974ce0df0808e2d9a81d564e50bbe2e0b316184645559c7387061da171eaa72`, own-source receipt `74dd084146efd0532fa5f5dfb2d2d82af1dc3b0e0605a9cec84085a502b08118`, and independent DATA review `6d0bb5c69416bbc9c16937be1ae0f09e1248a80f5ac23ab372a1fe1d66256121`.

The earlier unfused meter package, its goldens, transfer/history corpus and 128 atomic-rejection checks remain separate historical evidence. They have not been requalified for this fused implementation. The 13-case test does not exercise transfer construction, the complete sample/history/activity state machine, the whole finite domain, or invalid/alias rejection boundaries. Sanitizers, original numerical equivalence, callable native ABI, native state layout, table initialization/ownership, exception-status parity, host/audio integration, VST/AU classes and full-plugin reconstruction remain unverified. Native instruction observations motivate the arithmetic; the synthetic tests are not installed-LABS calls.

No commercial binary, captured table, asset or decompiler body is included. The independently written package uses the included MIT license.
