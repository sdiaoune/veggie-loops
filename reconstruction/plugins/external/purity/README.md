# Purity envelope curve primitive

This MIT component independently generates one mathematical envelope curve.
It contains no commercial table bytes, preset, sample, binary or decompiler
output. It uses a new C ABI with caller-owned output storage and a disclosed
finite amount domain. It is not a Purity plugin, voice pipeline or state loader.

```sh
./reconstruction/plugins/external/purity/verify.sh
```

The arm64-only identity-bound fixture calls the exported mathematical helper
from the inspected Purity VST1.4.5.1 binary as a read-only comparison oracle.
That original binary is not a dependency of the rebuilt curve library.
The test compares all259 output floats, including interpolation padding,
and checks output guards and atomic invalid-argument rejection in the new ABI.
Amount bounds are the tested reconstruction domain; no claim is made that
the native helper rejects the same invalid inputs.

The installed binary's4,459 identified internal non-thunk arm64 procedures
have local REA decompiler results. This measures identified-procedure analysis
coverage, not source reconstruction, whole binary coverage or recompilation.
Purity's audio engine, samples, parameters, state, MIDI, editor, factories,
host integration and other architectures remain outside this primitive.
