# Native plugin verification hosts

These original command-line hosts load an instrument through its advertised
VST2, VST3 or AU factory. They check construction, float processing,
MIDI note-on/off, finite nonzero audio, a state export/restore and teardown.
They do not establish full plugin equivalence or integrate plugins into the
VL Studio application. Effects, GUI, automation, preset libraries, additional
rates/layouts and other architectures need separate verification. Loading an
installed original establishes reference behavior and is not recompilation.

Build on macOS using a locally supplied VST3 SDK. The currently checked SDK is
the one supplied with the GPL upstream Vital repository's JUCE 6.0.5. Neither
the SDK nor upstream plugin source is included in this MIT source tree.

```sh
bash reconstruction/plugins/common/build_hosts.sh /absolute/path/to/VST3_SDK arm64
bash reconstruction/plugins/common/build_legacy_host.sh arm64
bash reconstruction/plugins/common/build_legacy_host.sh x86_64
```

The script prints the private output directory. Each host accepts an absolute
plugin bundle path and an optional private diagnostic filename prefix. The
VST3 host also accepts an optional captured input-state file after that prefix.
Its audio diagnostic is interleaved little-endian float32 stereo at 48 kHz.
The AU host registers the supplied component inside its process and does not
install it. Diagnostic states and audio stay in ignored local directories.
The build scripts sign only their own generated hosts with a local ad-hoc
signature. An unsigned Intel host stalled before `main` in the tested local
environment; the signed copy started and completed its tests.

The VST2 host uses an original 64-bit protocol record and does not require a
commercial VST2 SDK. Its arguments are the bundle, optional private prefix,
optional input-state filename (or `-`), sample rate and block size. A rate
between 8,000 and 192,000 Hz and block size between 1 and 8,192 are accepted by
the harness; this is not a claim that every plugin supports that whole range.
The tested installed Purity, Intel Vital and Intel TyrellN6 each produced
finite nonzero audio at 44,100/64, 48,000/512 and 96,000/1,024. It uses zeroed
audio inputs, the plugin's advertised output count, and two seconds of MIDI
note-on/off. Output diagnostics interleave all advertised output channels.
The tested LABS default loaded and serialized state but produced silence.
VST2 state restore return values and byte equality are measurements, and
`state_semantics_verified=false` is explicit until a plugin-specific check.
The callback counter is atomic and transport snapshots are thread-local and
protected by a mutex. This offline host does not establish real-time safety,
GUI hosting, controller automation, scheduling or arbitrary plugin compatibility.

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
in the tested AU, VST3 and VST2 state pairs. The fix is a disclosed behavior change, so this build
is not certified as an exact reconstruction of installed Vital. Upstream GPL
and SDK licenses remain separate from the original verification host license.
