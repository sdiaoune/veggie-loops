# Contributing to Veggie Loops

Build on macOS 14 or later with Xcode 16 or later, or a compatible Swift toolchain.

```sh
./script/build_and_run.sh
swift test
./script/verify-reconstruction
swift run VLSmoke dist/verification
```

`swift run VLSmoke dist/verification --playback` also verifies audio through your output device. Use this locally when changing playback. Omit `--playback` to verify rendering without playing sound.

An optional GitHub Actions configuration is provided in [docs/ci-workflow.example.yml](docs/ci-workflow.example.yml). Copy it to `.github/workflows/ci.yml` to enable automated macOS builds, tests and demo rendering. Publishing that workflow requires a GitHub credential with workflow permission.

## Code layout

- `Sources/VLCore`: musical model, document validation and persistence.
- `Sources/VLDSP`: mixer and effects.
- `Sources/VLNativeDSP`: C++ bridge to the reconstructed raw oscillator core.
- `Sources/VLAudio`: synthesis, sample decoding, native playback and WAV export.
- `Sources/VLStudio`: macOS app, state and interface.
- `Sources/VLSmoke`: audio and document integration checks.
- `Tests`: Swift behavioral tests.
- `reconstruction`: independently written FLP framing parser and selected native behavior reconstructions.

Open an issue for bugs or feature proposals. For a pull request, describe the resulting behavior and the checks you ran. Keep changes focused; include behavioral tests for timing, signal processing, document compatibility or cancellation changes. Exercise interface changes in the running app.

The app currently uses one pattern per channel and its own `.vlp` format. Keep proposed FLP interpretation separate from verified framing and preserve unknown payloads. See [research scope](docs/RESEARCH.md).

Submit original work under MIT for the workstation and reconstruction modules.
The optional `reconstruction/plugins/external/vial/` module explicitly uses
GPL-3.0-or-later; contributions there must preserve that license and upstream
notices. Do not add FL Studio binaries, decompiled source, commercial factory
payloads, plugin binaries, samples, license data or captured user projects.
Builds, exports and local research evidence are ignored by Git.
