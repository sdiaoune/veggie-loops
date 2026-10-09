# Prepared lookup

This small C++20 package provides `vl::labs::prepared_lookup::lookup_prepared`, an independently written interpolation API over a caller-owned, stable table. It models a statically examined prepared lookup path and uses an explicit fused multiply-add for the final interpolation. It does not load an installed plugin or initialize its globals.

The caller must supply live, correctly aligned storage and serialize table/output access. Tables contain 1 through 2^24 floats, each finite and in [0,1]; both signs of zero are accepted. Input is finite and in [-2,2]. The output must not overlap the table. These are defensive limits of this new API, not measured bounds or contents of a native table. A rejected call leaves the output unchanged. Accepted calls validate the entire table, then clamp to endpoints or interpolate; this full scan has no real-time performance certification.

Compile for IEEE binary32 with nearest-even rounding, gradual underflow, masked traps, no fast-math or excess precision, and floating-point contraction disabled except for explicit `std::fma`. The implementation depends only on its two source files and a C++20 toolchain. The supplied nine-check numerical test reads ARM64 FPCR and deliberately refuses other platforms; its measured environment is macOS arm64 with Clang. Portability of the library's arithmetic outside that environment needs separate validation.

From this directory, a macOS arm64 source check can be built and run using the C++ toolchain and built-in signing tools:

```sh
mkdir build
clang++ -arch arm64 -std=c++20 -O2 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror prepared_lookup.cpp test_prepared_lookup_arm64.cpp -o build/test_prepared_lookup_arm64
codesign --force --sign - build/test_prepared_lookup_arm64
codesign --verify --strict build/test_prepared_lookup_arm64
./build/test_prepared_lookup_arm64
```

The test checks a synthetic nearest-even, finite-normal interpolation witness (`0x3e940ad7` fused versus `0x3e940ad6` with separate multiply/add), signed-zero/endpoints, a singleton table, and three rejection/preservation cases. Checks remain active without `assert`. It reports nine successful checks and both `original_plugin_called` and `full_plugin_equivalence` as false. The public package compiled with no diagnostics and passed these nine checks with FPCR 0 on macOS arm64. Its product passed strict ad-hoc signature verification. These checks cover the disclosed own-source cases; they do not certify the full numeric domain or an installed plugin.

Historical private evidence is referenced only by literal digest; none is a build or runtime dependency:

- Source reviews: `25d122e25d2155f7bfd95b9dd13cc161b10a4911b6076c046eb08655078aa90b` and `b11dbffbd8e37c9655f160fb9fd66d99f51ae8157e2cae42d3df87333a4edb4b`.
- Own-source test receipt: `019a2a1d3c872d35ce977828f316ecfc5e10a5bc939be3261734f766c8fdc076`.

Native table allocation, initialization, ownership and guard/slow-path behavior; callable ABI; original numerical equivalence and exception-status/trap/FZ behavior; audio routing and whole-plugin equivalence remain unproved. The synthetic witness establishes an own-source arithmetic result, not the result of an installed LABS call. Full reconstruction is false. No commercial binary, table contents or decompiler output is included. The independently written sources use the included MIT license.
