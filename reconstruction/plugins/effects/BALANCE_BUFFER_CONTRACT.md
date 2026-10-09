# VL Balance C API buffer contract

Caller buffers must have live, suitably aligned storage and the declared size. Calls for one instance must be serialized. Nonempty input/output spans must not overlap any bytes of that instance. Meter outputs must be separate. Stereo render buffers may be exactly identical; partial overlap is refused. A rejected call preserves the instance and output buffers.

The source check compares ordered unsigned address differences, without forming end addresses. Parameter, render, meter, save and restore guards run before mutation. This fixes a new-C-API bug where a legal own fixture could pass the pan member as the result of a volume getter and overwrite pan with 256. The original native scalar-return callback has no corresponding result pointer.

The own arm64 regression fixture checks nine atomic alias refusals, valid external state/parameters/meters, an output immediately following a live embedded instance, and separate/exact-in-place rendering. The existing API regression also passes. The private comparison preserved an actual pre-fix reproduction. This changes buffer handling; DSP math and the 0..1024 frame cap are unchanged. Larger original callbacks, native ABI, host integration, x86/VST/AU formats and complete-plugin equivalence remain unverified.

From the repository root on macOS arm64:

```sh
clang++ -arch arm64 -std=c++20 -O2 -ffp-contract=off -fno-fast-math \
  -fno-builtin-sin -fno-builtin-cos -fno-builtin-exp -Wall -Wextra -Werror \
  reconstruction/plugins/effects/test_balance_object_alias.cpp -o /tmp/vl-balance-alias
codesign --force --sign - /tmp/vl-balance-alias
codesign --verify --strict /tmp/vl-balance-alias
/tmp/vl-balance-alias
```

The fixture includes the own implementation so its pointers refer to legal live members. Its historical comparison macro is used with the retained pre-fix implementation; the default build exercises the repaired contract. No commercial plugin or private analysis files are needed for the default build.

The public working tree and a clean checkout of code commit `7eab456a680c36c9afd0bcd35db735e227c14271` both passed the alias and existing API checks. All four public-replay products were ad-hoc signed, strictly verified and checked as arm64; all seven selected source/document files stayed exact during each run and the clean checkout remained unmodified. Retained replay receipt: SHA256 `96d22442bbe1549f1a8850f6c7299b7eea49b62eb178d34d250832994369fe34`. This final update changes only documentation and validation metadata.
