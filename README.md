# Veggie Loops / VL Studio

**Veggie Loops / VL Studio** is an MIT-licensed native macOS music workstation, with an original audio engine and interface. It includes a sequencer, piano roll, arrangement editor, mixer, built-in instruments, sampler and WAV export. This is an early playable version; its current limits are listed below.

The repository also contains independently written FLP framing and native behavior reconstructions. See [research scope](docs/RESEARCH.md) for the investigation and verified boundaries.

## Play music

Requires macOS 14 or later and Apple's Swift toolchain to build. No external package dependencies are needed.

```sh
git clone https://github.com/sdiaoune/veggie-loops.git
cd veggie-loops
./script/build_and_run.sh
```

This builds and opens **dist/VL Studio.app**. The Codex **Run** action uses the same script. The app opens with the original **Fresh produce** demo groove; press **Space** or the green Play button to hear it. Space stops playback and returns to the start.

- **Channel rack:** click steps to add or remove notes on a sixteenth-note grid. Add kick, snare, hat, bass, synth or sample channels from the + menu.
- **Piano roll:** select a channel, click empty grid cells to add notes, then select a note to edit pitch, start, length and velocity. Piano keys preview notes. Delete selected notes with the inspector or context menu.
- **Arrangement:** click a bar to place the channel's pattern, or click a clip to remove it. Choose **Song** in the transport to play the arrangement; **Pattern** plays the channel patterns together.
- **Mixer:** drag channel/master faders, set pan, mute or solo channels, and adjust low-pass cutoff, drive and delay send. Shared delay time and feedback follow the tempo. Playback refreshes after edits while keeping musical position.
- **Projects:** ⌘S saves a `.vlp` document, ⌘O opens one, ⌘Z undoes edits, and ⇧⌘Z redoes them. Unsaved changes trigger a native save/discard prompt.
- **Samples and export:** ⌘I imports user audio; sample pitch C4 preserves the source pitch. **Export WAV** or ⇧⌘E renders the selected Pattern/Song mode to 48 kHz stereo, 16-bit PCM.

Projects support up to **16 channels**, **1–4 bars per channel pattern**, **16 song bars**, and **40–240 BPM**. Each channel currently has one pattern, repeated within its arrangement clips. Imported samples are referenced by absolute path and must remain available; files under two minutes and 256 MB are accepted. This version supports its own `.vlp` documents, built-in instruments and a sampler. FLP musical import, VST/AU hosting, microphone recording and multiple patterns per channel are future work.

## Verify the workstation

```sh
swift test
swift run VLSmoke dist/verification --playback
./script/build_and_run.sh --verify
./script/verify-reconstruction
```

The **22 Swift tests** cover project persistence/validation, the mixer, synthesis, note timing, song placement, sample decoding/resampling, WAV export and cancellation. `VLSmoke` additionally renders a demo song, decodes the WAV, roundtrips its project, and checks actual native playback, advancing transport, meters, live refresh and Stop. Its generated demo files and JSON report are in `dist/verification/`. `--playback` briefly plays audio through the current output device.

The native UI was exercised for sequencer edits and undo, piano-roll creation/length/velocity, arrangement placement/removal, project save/reopen, sample import and WAV export. See [app verification](analysis/app-verification.json) for the recorded checks.

The Swift package separates `VLCore` (documents/music model), `VLDSP` (signal processing), `VLAudio` (synthesis/playback/export), `VLStudio` (app/state/views), and `VLSmoke` (integration verification). File ownership and shared APIs are recorded in [the development contract](docs/DEVELOPMENT_CONTRACT.md).

## FLP analysis CLI

No Python dependencies are required. From this workspace:

```sh
./script/vl-studio inspect '/absolute/path/to/project.flp'
./script/vl-studio roundtrip '/absolute/path/to/project.flp' '/absolute/path/to/new-copy.flp'
```

`roundtrip` refuses to overwrite an existing destination. It preserves the original framing and payloads; it does not make musical edits. For an installable CLI, install `./reconstruction` in your own Python environment, then run `vl-studio`.

Run the portable parser checks:

```sh
./script/verify-reconstruction
```

The optional native differential workflow is documented in [research scope](docs/RESEARCH.md). It requires the exact investigated FL Studio build and unpublished local research helpers. It is separate from building and testing the workstation.

## Reconstruction scope

The code under `reconstruction/` is independently written. FL Studio, its plugins, samples, project payloads, decompiler output and private analysis slices are not published in this repository or packaged into VL Studio. Opaque FLP records are preserved rather than assigned unverified meanings.

The native workstation under `Sources/` implements its own musical model, synthesis, timing, mixer and interface. It does not claim whole-application equivalence to FL Studio or derive unverified FLP pitch/velocity meanings from opaque records.

## Contributing and license

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the code layout and verification workflow.

Original source code and documentation in this repository are available under the [MIT License](LICENSE). External applications, user-imported samples and locally generated research evidence are not included in that grant.
