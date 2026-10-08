# 3x Osc voice output primitives

This independent source rebuilds circular and compensated linear pan gains and
the block gain slew calculation. It does not yet connect them to the per-voice
filter, final audio mixer, native Fruity factory or actual host preferences.
The exported C functions have the prepared-domain preconditions in
`three_osc_voice_output.hpp`; callers supply valid writable output pointers.

Run `./reconstruction/plugins/generators/verify-voice-output.sh` on macOS arm64
with the identity-matched FL Studio 2024 installation. The script builds an
independent dynamic library, loads it separately from the read-only installed
wrapper, compares 120,000 pan cases and 60,000 slew cases bit for bit, then writes
`voice-output-verification.json` with source, artifact and target identities.
No commercial asset, table data or captured source is embedded in the library.

The native circular whole helper is checked with observed pan law 0. The linear
primitive is checked separately using the observed compensation factor, without
changing native globals. Both positive and negative zero and out-of-range pan
clamping are covered. Slew cases cover direction, frame count, maximum step and
the native silence threshold, including signed-zero behavior.

Darwin's joint `__sincosf` operation is required for the exact circular replay;
the portable fallback has not been proved bit-identical. These isolated normal
arithmetic comparisons do not establish full generator, Fruity, VST, AU or FL
Studio equivalence. The editor, allocation/unwind/invalid calls, voice filters
and final mixer remain outside this module.
