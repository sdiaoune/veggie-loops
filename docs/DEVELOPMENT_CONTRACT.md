# VL Studio implementation contract

File ownership prevents concurrent edits. Root alone owns Package.swift, Sources/VLCore, Sources/VLStudio/App, Sources/VLStudio/Stores, Sources/VLSmoke, Tests/VLCoreTests, script, README and docs. Audio agent alone owns Sources/VLAudio and Tests/VLAudioTests. Mixer agent alone owns Sources/VLDSP and Tests/VLDSPTests. Interface agent alone owns Sources/VLStudio/Views. No agent changes another owner's files; propose API changes to root first. Root runs the full package build and integration checks.

Models and public initializers are in Sources/VLCore/Project.swift. A track contains one pattern, in beat units, repeated within its arrangement clips. MIDI pitch is 0...127; velocity 0...1. Steps are quarter beats, 16 per bar. Pattern mode loops the pattern; song mode loops arrangementBars. Original procedural instruments only. Sample paths reference user-imported audio. Do not copy FL Studio assets or modify FL Studio.

## Mixer API (VLDSP)

`public enum DSPMixer` with `public static func mix(monoBuffers: [[Float]], settings: [MixerSettings], master: MasterSettings, sampleRate: Double, tempo: Double) -> StereoBuffer`.

Buffers have identical lengths, including any desired effects tail. Mixer handles mute/solo, gain, equal-power stereo pan, lowpass cutoff, drive, shared tempo delay send/feedback and bounded master output. Must produce finite samples. Pure Swift offline render; no AVFoundation dependency. Test musical behavior, pan, mute/solo, effects and safety.

## Audio API (VLAudio)

`public enum AudioRenderer` with synchronous throwing static methods:
- `render(project: VLProject, mode: PlaybackMode = .pattern, sampleRate: Double = 48000) throws -> StereoBuffer`
- `writeWAV(_ audio: StereoBuffer, to url: URL) throws`
- optionally `renderTrack(track: Track, project: VLProject, mode: PlaybackMode, sampleRate: Double) throws -> [Float]` for tests/meters.

`@MainActor public final class VLAudioEngine` with public init; read-only `isPlaying: Bool`, `currentBeat: Double`, `levels: AudioLevels`; `play(project: VLProject, mode: PlaybackMode) async throws`, `refresh(project: VLProject, mode: PlaybackMode) async throws`, `stop()`, and `audition(track: Track, midiNote: Int) async throws`.

Render off main thread, use AVAudioEngine and scheduled PCM loops. Edits refresh playback without stale renders winning. Native sample decoding/resampling. Real playback meters or position-based rendered meters. Stop must cancel pending plays. Tests verify nonzero instruments, note timing, song placement, WAV decoding, sample import. Root provides VLProject.validated() throwing method shortly; renderer can call it. No real-time Swift DSP callback allocations.

## App state consumed by interface (VLStudio)

`@MainActor @Observable final class AppState` in Stores. Observable properties: `project: VLProject`, `selectedTrackID: UUID?`, `editor: EditorPage` (enum cases sequencer,pianoRoll,arrangement), `mode: PlaybackMode`, `isPlaying: Bool`, `playheadBeat: Double`, `levels: AudioLevels`, `statusMessage: String`, `errorMessage: String?`, `isExporting: Bool`, `isDirty: Bool`. Computed `selectedTrack: Track?`, `canUndo: Bool`, `canRedo: Bool`. Views use `@Bindable` and the App owns `@State`; individual property observation keeps meter updates away from unrelated app menus and panels.

Methods:
- `edit(_ change: (inout VLProject) -> Void)` validation + undo + debounced playback refresh
- `toggleStep(trackID: UUID, step: Int)`
- `toggleNote(trackID: UUID, pitch: Int, step: Int)`
- `setNoteDuration(trackID: UUID, noteID: UUID, duration: Double)`
- `setNoteVelocity(trackID: UUID, noteID: UUID, velocity: Double)`
- `toggleClip(trackID: UUID, bar: Int)` toggles one patternBars-long clip at bar (one click per cell)
- `addTrack(_ instrument: InstrumentKind)`, `deleteTrack(_ id: UUID)`
- `audition(_ trackID: UUID, pitch: Int? = nil)`
- `togglePlayback()`, `stopPlayback()`, `changeMode(_ mode: PlaybackMode)`
- `newProject()`, `loadDemo()`, `openProject()`, `saveProject()`, `saveProjectAs()`, `exportWAV()`, `importSample(trackID: UUID? = nil)` (native file panels)
- `undo()`, `redo()`

Interface entry: `struct StudioView: View { @Bindable var state: AppState }`. UI agent owns Views only. Root owns @main App and menu commands. Create toolbar, instrument list, step sequencer, interactive piano roll with note length/velocity, arrangement clips, bottom mixer with faders/pan/mute/solo/effects/master. Use `state.edit` for bindings; never mutate project directly. Assign IDs/accessibility labels to main controls. Responsive native window; all visible actions functional. Use no external assets/dependencies.
