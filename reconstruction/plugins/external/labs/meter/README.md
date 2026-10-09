This directory contains an experimental caller-managed meter API and its own source-contract tests. It is an original implementation with explicit unfused arithmetic. It does not reconstruct a LABS plugin class, VST/AU format, synthesizer, sample playback, audio engine or commercial interface, and it makes no original LABS numerical, ABI, instruction, fusion, exception-status, global-state or allocator equivalence claim. Full-plugin reconstruction remains false.

`meter.hpp` states the supported storage, finite-number, overlap, serialization and floating-point preconditions. The caller supplies 1000-element transfer tables and 100 ordered thresholds. The tests use synthetic caller data, including nonmonotone lookup tables, repeated thresholds, adjacent float values and signed zeros. No captured commercial threshold table or original plugin is needed or supplied. Defensive rejection is a contract of this new API rather than a claim about original malformed-input behavior.

The four C++ files are byte-identical to the accepted private V2 source. The typed scalar oracle, nine mutation commitments and exact generated-source hashes are also retained. Three profiles (O2, fatal ASan/UBSan/float-cast-overflow O2 and O0) check 16 lookup boundaries, four threshold builds, nine state boundaries and 128 valid-live-storage atomic rejections per profile. Nine fatal semantic mutants must each return 1 with empty stdout and its exact assertion diagnostic, rather than fail by a sanitizer. The repeated-threshold commit mutant is discriminated by interior rows as well as the other table checks. These are bounded tests of this source's own contract.

The standalone replay requires Python 3.9 or newer, macOS arm64, `clang++` with its sanitizer runtime, `codesign` and `lipo`. It requires only the nine files in this directory and those tools. No installed plugin, SDK, private report, decompiler output, image slice or Git checkout is read. Historical proof hashes below are literal references, not dependencies of the recipe. Python optimization is refused before source reads, outputs or subprocesses. A closure-only check creates no outputs and invokes no tools:

```sh
python3 verify.py --check-only
```

For a replay, first reserve sole use of the compiler with the other project workers. The explicit lease marker does not grant a lease by itself. Choose a fresh directory whose parent already exists; it must be separate from this source directory:

```sh
VL_LABS_METER_SOURCE_SLOT_GRANTED=1 python3 verify.py --work /tmp/vl-labs-meter-public-check
```

An optional `--manifest-sha256 DIGEST` pins the release's `verification.json` externally. The package manifest binds the other eight public files, including the recipe and README; the manifest's own identity is captured before replay and audited after it. The recipe refuses duplicate/traversing source names, stale work directories, source/work overlap, unexpected counts or scalar types. Every product is ad-hoc signed, strictly verified and checked as arm64 before execution. Compiler and positive-runtime diagnostics fail the replay, and fatal instrumentation cannot recover into a successful result.

All four compile copies, nine future mutant sources, generated execution map and registry are registered with their expected identities before the work directory or any child is created or written. The source closure, manifest and every registered expected output are audited independently in `finally` after setup, partial-copy, command or recording failure. Command logs, result records and products are additionally registered before their operations; product identities are sealed after strict signing and before use. Pending, missing, partial or changed outputs fail the final audit. Primary and publication/recording failures remain distinct.

Result publication is protected, followed by another complete audit, protected final-report publication and a final audit including that report. A pass-labelled `result.json` by itself is not an accepted replay: the caller must retain a clean process exit, the success stdout and the final identities/artifact audit. A write that emits a whole file and then reports an error still fails. Work and failed outputs are preserved; the recipe never deletes or reuses them. Setup failure before a work directory exists is reported on stderr with all attempted source/output audit rows and cannot be a pass.

The public working layout passed its standalone source replay: all three typed profiles, nine semantic negatives and twelve strictly signed arm64 products. Four early recipe refusals and a nine-identity closure check passed. Root independently rechecked the recorded inputs, outputs and product signatures; the retained replay receipt is SHA256 `a315f63f6156a5664d73363d0d5f66153d4d4fa4f213f708aa4203f7bb6482bc`. A fresh public checkout replay remains a separate gate. Its accepted private source history is separate from public packaging acceptance. The first independent runtime wrapper's metadata comparison failure remains preserved and ineligible; a later data-only correction qualified the unchanged completed source runs without rewriting that failure. The combined two-critic acceptance applies only to the bounded own-source contract:

- Combined private source-runtime acceptance: SHA256 `4f0d71b4dac03ff361e1320256e90a0fced22c8ca972d23f4cf993bb92dec561`.
- Root's independent retained-run metadata audit: SHA256 `628a8520a8df539bd360d08d0c17bb2714678f3fa926aad7177d63ad43f50e4e`.
- Qualified first completed-run metadata proof: SHA256 `b45e22576af312e5356171272c07a67bc2b33e645d147a2739d1ddd90b169e37`.
- Second independent copied-source runtime review: SHA256 `615170fd65a04a5ad1183d5b9cd073bd2545a91e5849c3364621806d93978317`.
- Retained old first-wrapper failure: SHA256 `2df808d956319355fe67bf70e6612c8ac461c7bfec73a04386cfaf4ce65447aa`.

These hashes do not assert original-plugin parity, general floating-point environment equivalence, audio behavior or full reconstruction. Future public-layout static reviews and source-only replay are separate gates.
