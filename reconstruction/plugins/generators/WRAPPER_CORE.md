# 3x Osc wrapper core

The installed Fruity wrapper has 114 controls and a version-14 preset containing
a 4-byte version followed by 456 bytes. This original C++ component reconstructs
the 21 oscillator controls, storage/normalization for the integrated editor's
85 fields and three globals, five reserved control slots, the version-14 payload,
and raw HQ/legacy per-voice processing. HQ uses the separately reconstructed
small engine; legacy mode consumes host-supplied synthetic waveform tables.

`three_osc_wrapper_core.h` exposes a new C ABI. It does not implement the native
`CreatePlugInstance` factory. Integrated-editor envelope/filter/modulation DSP,
final generator mixing, GUI, old preset formats, voice stealing, and FL/VST/AU
host integration remain unfinished. Control storage alone does not implement
the corresponding modulation processing.
Release records a voice's release state but does not synthesize an envelope.

The host supplies the pan/volume callback, matching the native boundary. No
particular FL Studio pan law is embedded or claimed. Calls are serial because
the small engine and native Pascal wrapper use shared random/lifecycle state.

Run `./reconstruction/plugins/generators/verify_wrapper.sh` to compile original
source, or add `--native` on the reviewed macOS arm64 installation to test the
actual reconstructed dylib against the installed native factory. The script
regenerates the sanitized source/target manifest. Target hashes are checked before
loading. Synthetic waveforms and preset payloads exist only in memory; original
commercial assets and executable bytes are not included in compiled artifacts.

The differential fixture supplies a controlled equal-power host callback and
reads the native Pascal MT19937 state once per case to initialize only the new
library. Native API calls then perform both voice triggers and all render blocks;
the sequence is compared without resynchronizing that random state between them.
The separate engines' noise seeds are synchronized at block boundaries because
their globals are independent. Outputs, derived arithmetic, phases, stereo,
control values, 453 defined output bytes, and live-voice counts are checked
exactly. Of these, 441 field bytes are preserved and 12 reserved bytes at
payload+432..439/+448..451 are ignored on restore and zeroed on save. The corpus
mutates all 12 reserved input bytes, then compares native canonicalization.
The native three bytes at payload+89 are undefined stack padding;
the independent serializer writes zero. Editor data starts at payload+92.
Legacy mode uses 16384-sample host tables and separately rounded multiply/add;
render flag 2 also tests the native multiple-phase averaging branch.

The supported valid control/sample-rate/pitch domains are documented in the
header. Invalid inputs are defensively rejected; invalid-input/native exception
behavior is outside the equivalence claim.
