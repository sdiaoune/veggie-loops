# Native plugin verification hosts

These original command-line hosts load an instrument through its advertised
VST3 or AU factory. They check construction, one stereo float configuration,
MIDI note-on/off, finite nonzero audio, a state export/restore and teardown.
They do not establish full plugin equivalence or integrate plugins into the
VL Studio application. Effects, GUI, automation, preset libraries, additional
rates/layouts and other architectures need separate verification.

Build on macOS using a locally supplied VST3 SDK. The currently checked SDK is
the one supplied with the GPL upstream Vital repository's JUCE 6.0.5. Neither
the SDK nor upstream plugin source is included in this MIT source tree.

```sh
bash reconstruction/plugins/common/build_hosts.sh /absolute/path/to/VST3_SDK arm64
```

The script prints the private output directory. Each host accepts an absolute
plugin bundle path and an optional private diagnostic filename prefix. The
VST3 host also accepts an optional captured input-state file after that prefix.
Its audio diagnostic is interleaved little-endian float32 stereo at 48 kHz.
The AU host registers the supplied component inside its process and does not
install it. Diagnostic states and audio stay in ignored local directories.

Byte-equal state serialization is reported as a metric. Plugin-specific state
semantics require an additional check. `validate_vital_state.py` checks captured
Vital/Vial JSON and AU envelopes, all persistent settings, and little-endian
PCM16 sample payloads with a declared maximum difference of one PCM unit. That
tolerance accounts for the upstream float/PCM conversion; it does not permit
sample shifts, missing data or changed settings. It covers only the supplied
state pair and does not prove arbitrary presets or version equivalence.

The local upstream source build identifies itself as Vial 1.0.6; the installed
Intel Vital is 1.0.7. An independently observed upstream sample-state bug omits
the four-sample padding offset when serializing samples. The private source
build corrects that offset. The original installed 1.0.7 also exhibits the shift
in the tested state pair. The fix is a disclosed behavior change, so this build
is not certified as an exact reconstruction of installed Vital. Upstream GPL
and SDK licenses remain separate from the original verification host license.
