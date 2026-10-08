# Reconstruction research

Veggie Loops contains an independently written native music workstation and a separate investigation of selected FL Studio behaviors. The app has its own musical model, instruments, mixer and interface. It does not claim complete FL Studio compatibility.

The original local investigation used [REA](https://github.com/morluto/rea) 6.0.0 and Ghidra 12.1.4 against FL Studio 24.1.1.3936 on Apple Silicon. The public source includes the independently written parser, native reconstruction code and test harnesses. Captured disassembly, decompiler output, tool records, private binary slices and factory project payloads remain local and are excluded from Git.

## Verified components

- The bounds-checked FLP parser preserves chunk framing, event framing and unknown payloads. Thirteen portable tests cover parsing, serialization, malformed inputs and CLI behavior.
- A local corpus check roundtripped 36 factory templates in memory: 122,028 events and 32,118,675 bytes preserved exactly. Templates are not distributed.
- A capability callback and legacy argument adapter matched the isolated original routines in 16,741 differential cases.
- A floating-point gate, with four external calls stubbed, matched in 14,997 differential cases.
- Neutral 24-byte note storage preserved 1,011 candidate records. This verifies byte storage; pitch and velocity meanings remain unresolved.

These counts describe the investigated version and bounded components. They do not establish whole-application equivalence. The [verification summary](../analysis/verification-summary.json) retains the measurements; [app verification](../analysis/app-verification.json) covers the independently implemented workstation.

## Portable checks

```sh
./script/verify-reconstruction
./script/vl-studio inspect /absolute/path/to/project.flp
./script/vl-studio roundtrip /absolute/path/to/project.flp /absolute/path/to/new-copy.flp
```

The CLI preserves framing and payloads. It does not import FLP musical content into the app or make musical edits. `roundtrip` refuses to overwrite an existing destination.

## Local research checks

`./script/verify-reconstruction --local-native` retains the original local corpus and differential workflow. It requires macOS arm64, the exact investigated FL Studio build and the unpublished research helpers under `analysis/flp/`. Those helpers and evidence are present in the original workspace; they are not included in a fresh clone.

The two native test harnesses under `reconstruction/native/` read the user's installed binaries, verify their digests and execute bounded routines with stub inputs. They contain no FL Studio binary payload. REA session scripts under `script/` retain tool responses in ignored `analysis/` directories; they are optional research utilities, not app dependencies.
