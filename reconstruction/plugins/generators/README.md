# Generator reconstruction

The installed bundle contains **58 generator dylibs across 49 folders**.
This directory currently reconstructs the separate **3x Osc small DSP engine**,
identified by SHA-256
`d7eda5267ae938c22ca36d11676ffd870d639aec6086954cd7e895b04be8e66f`.

The independently written C++ implementation rebuilds its sample-rate/pitch
math, oscillator waveforms, shared noise generator, ring modulation,
four-lane mixed-radix FFT, mipmap generation, custom-wave averaging,
factory tables, lifecycle and command dispatcher. The rebuilt library also
supplies all 45 original public symbol names, including the observed C++ class
ABI. A symbol name alone is not behavioral proof; the tests exercise those
families through the compiled library and compare numeric outputs bitwise.

```sh
./reconstruction/plugins/generators/verify.sh --native
```

This requires the exact reviewed local installation, macOS arm64 and Apple's
command-line compiler. Without `--native`, the script only builds the two
independently reconstructed dylibs. Outputs remain under ignored
`.tools/plugin-work/generators/`. [verification.json](verification.json) records
source and build hashes, per-gate measurements, and explicit limitations.

The small-engine dispatcher uses a 72-byte oscillator object and opcodes
0/create, 1/destroy, 2/integer sample rate, 3/custom wave (16,384 input floats),
and 10/11/12/render. Rendering uses the packed 28-byte `RenderArguments`
structure declared in [three_osc.hpp](three_osc.hpp); it processes one lane of
an interleaved buffer. Opcode 11 clears that lane first; opcode 12 applies ring
modulation. Calls must be serialized because the RNG and factory lifetime are
shared. Use the documented waveform, buffer, table, rate and frame bounds.
The low-level public mipmap generation routine requires a freshly constructed
or cleared destination; it overwrites allocation pointers as the native
routine does. Rebuilding a complete `WaveTable` clears its previous maps.

Later modules reconstruct bounded wrapper controls, version-14 state storage,
automation, multi-voice channels, envelopes/filters, an experimental C++ factory
and prevoice context delivery. Their separate proofs and limits are listed in
[the module status](../STATUS.md), [native factory](NATIVE_FACTORY.md) and
[prevoice delivery](CONTEXT_DELIVERY.md). Complete original class/editor/GUI,
application-owned clocks/tables/scheduling, general state/automation/polyphony
and VST/AU integration remain unfinished. The library is not
installed over FL Studio's engine. No commercial binary, captured machine
code, disassembly or asset is bundled in it. Native failure/exception paths,
allocation tracing and malformed input behavior remain outside the proof.
Factory teardown clears its global pointer defensively; the reviewed native
implementation leaves a stale pointer until another constructor replaces it.

Local REA/Ghidra evidence is retained under ignored
`analysis/plugins/generators/three-osc/`; all 38 nonexternal, nonthunk procedure
bodies were decompiled. The procedure ledger distinguishes normal processing
proof from the compiler-generated exception/termination helper. Isolated
subprocess tests compare the native and newly compiled helper's call order,
argument preservation and real `std::terminate` behavior; `begin_catch` is an
observation stub, so exception-object layout/unwinding parity remains unproved.
