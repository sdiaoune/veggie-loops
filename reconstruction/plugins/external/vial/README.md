# Vial source-build research

This optional GPL component is separate from the MIT workstation. It builds
the public [upstream source](https://github.com/mtytel/vital) at commit
`636ca0ef517a4db087a6a08a6a8a5e704e21f836`, whose plugin is named **Vial 1.0.6**.
The inspected installed plugin is **Vital 1.0.7**. This version gap remains;
these builds do not establish complete reconstruction of that installed plugin.

On an arm64 Mac with Xcode and Python 3, run:

```sh
./reconstruction/plugins/external/vial/build.sh /absolute/path/to/new-build-directory
```

The recipe clones the pinned public source, applies the disclosed sample-state
patch, and builds VST3, AU and an experimental legacy-format VST bundle. Output
stays in the new build directory. It does not install or replace any plugin.
The legacy wrapper uses an independently written ABI declaration rather than
the missing retired VST2 SDK. No installed target binary, captured preset,
commercial sound bank or decompiler output is needed by the build.

`sample-state-offset.patch` corrects a measured four-sample serialization offset
in the upstream source. This changes behavior relative to the installed
reference. Saved samples are PCM16; the tested source roundtrip has at most one
PCM16 unit of conversion error. The unpatched negative case remains recorded
locally and failed the same comparison.

The experimental wrapper supports serial caller-controlled initialization,
bounded sample rate/block configuration, 772 parameters, replacing stereo
audio, MIDI events and valid upstream JSON state chunks. Independent tests
cover repeated construction, parameter text bounds, short-block MIDI filtering
and the disclosed audio/state cases. It has no editor, host automation callback,
playhead, program-bank support or realtime guarantee. Its state operation has
the upstream loader's valid-input contract: malformed state can invoke an
upstream error dialog, and the wrapper does not promise atomic rejection of
arbitrary state. Do not interpret the bounded successful tests as a certificate
for arbitrary host or preset input.

The native hosts under `../../common/` can inspect the built bundles. Exact
audio results and tested boundaries are recorded in `verification.json`.
Factory loading, source recompilation and one deterministic comparison do not
establish installed-plugin version, GUI, preset-corpus or whole-plugin parity.

## License and assets

This directory's wrapper, patch and build recipe are **GPL-3.0-or-later**, under
the included [GPL license](LICENSE). This is an explicit exception to the
repository's MIT default. Preserve the upstream source, its notices and the
separate licenses in its `third_party/` and `fonts/` directories when preparing
any distribution. The script retains corresponding upstream source in the
build directory; it does not publish binary releases.

The upstream README excludes its separately licensed downloadable presets from
redistribution and gives no rights to use its product names or web services.
This research wrapper is named Vial Research. External source and assets remain
external dependencies with their own notices.
