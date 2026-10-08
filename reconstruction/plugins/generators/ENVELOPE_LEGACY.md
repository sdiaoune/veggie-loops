# Isolated envelope and legacy waveform components

These independently written C++ components supplement the separately reviewed
raw wrapper core. They are not yet connected to its voice pipeline, native
Fruity factory, FL/VST/AU host integration, filters, final mixer or GUI.

`three_osc_envelope.*` supplies the prepared 160-byte configuration, 36-byte
state, curve helpers and per-tick envelope/LFO transitions. Native comparison
covers 2,050 preparations and 2,840,400 state words.

`three_osc_envelope_coefficients.*` supplies coefficient preparation from
explicit tempo and raw clock inputs. 3,600 configurations and 144,000 words
compare exactly. Producing those clock inputs from actual host scheduling
remains unfinished.

`three_osc_legacy_tables.*` independently generates six 16,384-sample banks,
including sine, triangle, square, saw, quantized exponential and local noise.
All 98,304 samples and 81,000 PRNG integers over nine seeds compare exactly.
The measured local MT implementation overwrites word 226 twice and uses its
index field on the second pass. No commercial table bytes are embedded.

Run `verify-envelope.sh`, `verify-envelope-coefficients.sh` and
`verify-legacy-tables.sh` for their separate canonical comparisons. Each builds
an actual dylib, requires the reviewed native wrapper as a read-only oracle,
refuses non-arm64 native-address execution and refreshes its sanitized source,
artifact and target manifest. Low-level valid-domain contracts are in the
headers; unsupported invalid/allocation/unwind behavior remains explicit.
