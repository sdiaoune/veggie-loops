import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import VLCore
import VLAudio

enum EditorPage: String, CaseIterable, Hashable {
    case sequencer, pianoRoll, arrangement
    var title: String {
        switch self { case .sequencer: return "Channel rack"; case .pianoRoll: return "Piano roll"; case .arrangement: return "Arrangement" }
    }
}

@MainActor @Observable
final class AppState {
    private(set) var project: VLProject
    var selectedTrackID: UUID?
    var editor: EditorPage = .sequencer
    private(set) var mode: PlaybackMode = .pattern
    private(set) var isPlaying = false
    private(set) var playheadBeat: Double = 0
    private(set) var levels = AudioLevels()
    private(set) var statusMessage = "Ready · Space to play"
    var errorMessage: String?
    private(set) var isExporting = false
    private(set) var isDirty = false
    private(set) var currentFileURL: URL?

    var selectedTrack: Track? { project.tracks.first { $0.id == selectedTrackID } }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    private let engine = VLAudioEngine()
    @ObservationIgnored private var savedProject: VLProject
    private var undoStack: [VLProject] = []
    private var redoStack: [VLProject] = []
    @ObservationIgnored private var lastEditTime = Date.distantPast
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var wantsPlayback = false
    @ObservationIgnored private var transportGeneration = 0
    @ObservationIgnored private var timer: AnyCancellable?

    init(project: VLProject = .demo()) {
        self.project = project
        self.savedProject = project
        self.selectedTrackID = project.tracks.first?.id
        engine.onFailure = { [weak self] error in
            self?.stopPlayback()
            self?.show(error)
        }
        timer = Timer.publish(every: 0.075, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.wantsPlayback && self.engine.isPlaying {
                    if self.playheadBeat != self.engine.currentBeat { self.playheadBeat = self.engine.currentBeat }
                    if self.levels != self.engine.levels { self.levels = self.engine.levels }
                } else if !self.wantsPlayback {
                    if self.levels != self.engine.levels { self.levels = self.engine.levels }
                }
            }
        }
    }

    func edit(_ change: (inout VLProject) -> Void) {
        var next = project
        change(&next)
        guard next != project else { return }
        do { try next.validated() } catch { show(error); return }
        if Date().timeIntervalSince(lastEditTime) > 0.35 || undoStack.isEmpty {
            undoStack.append(project)
            if undoStack.count > 100 { undoStack.removeFirst() }
        }
        lastEditTime = Date()
        redoStack.removeAll()
        project = next
        isDirty = project != savedProject
        if !project.tracks.contains(where: { $0.id == selectedTrackID }) { selectedTrackID = project.tracks.first?.id }
        queueRefresh()
    }

    func toggleStep(trackID: UUID, step: Int) {
        guard let track = project.tracks.first(where: { $0.id == trackID }) else { return }
        let beat = Double(step) / 4
        guard beat >= 0 && beat < project.patternBeats else { return }
        let hasStep = track.notes.contains { abs($0.beat - beat) < 0.001 }
        edit { project in
            guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
            if hasStep { project.tracks[index].notes.removeAll { abs($0.beat - beat) < 0.001 } }
            else { project.tracks[index].notes.append(NoteEvent(beat: beat, midiNote: track.instrument.defaultPitch)) }
        }
    }

    func toggleNote(trackID: UUID, pitch: Int, step: Int) {
        let beat = Double(step) / 4
        guard (0...127).contains(pitch), beat >= 0, beat < project.patternBeats else { return }
        edit { project in
            guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
            if let note = project.tracks[index].notes.firstIndex(where: { $0.midiNote == pitch && abs($0.beat - beat) < 0.001 }) {
                project.tracks[index].notes.remove(at: note)
            } else {
                project.tracks[index].notes.append(NoteEvent(beat: beat, duration: min(0.5, project.patternBeats - beat), midiNote: pitch))
            }
        }
    }

    func setNoteDuration(trackID: UUID, noteID: UUID, duration: Double) {
        edit { project in
            guard let t = project.tracks.firstIndex(where: { $0.id == trackID }),
                  let n = project.tracks[t].notes.firstIndex(where: { $0.id == noteID }) else { return }
            project.tracks[t].notes[n].duration = min(max(duration, 0.0625), project.patternBeats - project.tracks[t].notes[n].beat)
        }
    }

    func setNoteVelocity(trackID: UUID, noteID: UUID, velocity: Double) {
        edit { project in
            guard let t = project.tracks.firstIndex(where: { $0.id == trackID }),
                  let n = project.tracks[t].notes.firstIndex(where: { $0.id == noteID }) else { return }
            project.tracks[t].notes[n].velocity = min(max(velocity, 0), 1)
        }
    }

    func toggleClip(trackID: UUID, bar: Int) {
        guard project.tracks.contains(where: { $0.id == trackID }), (0..<project.arrangementBars).contains(bar) else { return }
        edit { project in
            if let clip = project.clips.firstIndex(where: { $0.trackID == trackID && $0.startBar <= bar && bar < $0.startBar + $0.lengthBars }) {
                project.clips.remove(at: clip)
            } else {
                let length = min(project.patternBars, project.arrangementBars - bar)
                project.clips.removeAll { $0.trackID == trackID && $0.startBar < bar + length && $0.startBar + $0.lengthBars > bar }
                project.clips.append(ArrangementClip(trackID: trackID, startBar: bar, lengthBars: length))
            }
        }
    }

    func addTrack(_ instrument: InstrumentKind) {
        guard project.tracks.count < 16 else { errorMessage = "This project already has 16 tracks."; return }
        let track = Track(name: instrument.title, instrument: instrument, colorIndex: project.tracks.count % 8)
        edit { $0.tracks.append(track) }
        selectedTrackID = track.id
        if instrument == .sample { importSample(trackID: track.id) }
    }

    func deleteTrack(_ id: UUID) {
        edit { project in
            project.tracks.removeAll { $0.id == id }
            project.clips.removeAll { $0.trackID == id }
        }
    }

    func audition(_ trackID: UUID, pitch: Int? = nil) {
        guard let track = project.tracks.first(where: { $0.id == trackID }) else { return }
        Task { [weak self] in
            do { try await self?.engine.audition(track: track, midiNote: pitch ?? track.instrument.defaultPitch) }
            catch { self?.show(error) }
        }
    }

    func togglePlayback() {
        if wantsPlayback { stopPlayback(); return }
        wantsPlayback = true
        isPlaying = true
        statusMessage = "Preparing audio…"
        startPlayback()
    }

    private func startPlayback() {
        transportGeneration += 1
        let generation = transportGeneration
        let snapshot = project, playbackMode = mode
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.play(project: snapshot, mode: playbackMode)
                guard generation == self.transportGeneration, self.wantsPlayback else { return }
                self.statusMessage = "Playing \(playbackMode.rawValue) · \(Int(snapshot.tempo)) BPM"
            } catch {
                guard generation == self.transportGeneration, !Task.isCancelled else { return }
                self.stopPlayback()
                self.show(error)
            }
        }
    }

    func stopPlayback() {
        transportGeneration += 1
        wantsPlayback = false
        playbackTask?.cancel(); refreshTask?.cancel()
        engine.stop()
        isPlaying = false; playheadBeat = 0; levels = AudioLevels()
        statusMessage = "Stopped · Space to play"
    }

    func changeMode(_ mode: PlaybackMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        if wantsPlayback { engine.stop(); startPlayback() }
    }

    private func queueRefresh() {
        guard wantsPlayback else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
            guard let self, self.wantsPlayback, !Task.isCancelled else { return }
            let snapshot = self.project, playbackMode = self.mode
            do {
                if self.engine.isPlaying { try await self.engine.refresh(project: snapshot, mode: playbackMode) }
                else { self.startPlayback() }
            } catch {
                guard !Task.isCancelled else { return }
                self.stopPlayback()
                self.show(error)
            }
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project); project = previous
        afterHistoryChange()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project); project = next
        afterHistoryChange()
    }

    private func afterHistoryChange() {
        lastEditTime = .distantPast
        isDirty = project != savedProject
        if !project.tracks.contains(where: { $0.id == selectedTrackID }) { selectedTrackID = project.tracks.first?.id }
        queueRefresh()
    }

    func newProject() {
        guard confirmDiscard() else { return }
        replaceProject(.empty(), url: nil)
    }

    func loadDemo() {
        guard confirmDiscard() else { return }
        replaceProject(.demo(), url: nil)
    }

    private func replaceProject(_ project: VLProject, url: URL?) {
        stopPlayback()
        self.project = project; savedProject = project; currentFileURL = url
        selectedTrackID = project.tracks.first?.id
        undoStack.removeAll(); redoStack.removeAll(); isDirty = false
        lastEditTime = .distantPast
        statusMessage = "\(project.name) · Ready"
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.title = "Open a Veggie Loops project"
        panel.allowedContentTypes = [UTType(filenameExtension: "vlp") ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let loaded = try ProjectDocument.load(from: url)
            guard confirmDiscard() else { return }
            replaceProject(loaded, url: url)
        } catch { show(error) }
    }

    func openProject(at url: URL) {
        do {
            let loaded = try ProjectDocument.load(from: url)
            guard confirmDiscard() else { return }
            replaceProject(loaded, url: url)
        } catch { show(error) }
    }

    func saveProject() {
        guard let url = currentFileURL else { saveProjectAs(); return }
        save(to: url)
    }

    func saveProjectAs() {
        let panel = NSSavePanel()
        panel.title = "Save Veggie Loops project"
        panel.allowedContentTypes = [UTType(filenameExtension: "vlp") ?? .json]
        panel.nameFieldStringValue = "\(project.name).vlp"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    private func save(to url: URL) {
        do {
            try ProjectDocument.save(project, to: url)
            currentFileURL = url; savedProject = project; isDirty = false
            lastEditTime = .distantPast
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch { show(error) }
    }

    func importSample(trackID: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Import an audio sample"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let target = trackID ?? selectedTrackID,
           project.tracks.contains(where: { $0.id == target }) {
            edit { project in
                guard let i = project.tracks.firstIndex(where: { $0.id == target }) else { return }
                project.tracks[i].samplePath = url.path
                project.tracks[i].instrument = .sample
                project.tracks[i].name = String(url.deletingPathExtension().lastPathComponent.prefix(100))
            }
            selectedTrackID = target
        } else {
            guard project.tracks.count < 16 else { errorMessage = "This project already has 16 tracks."; return }
            let track = Track(name: String(url.deletingPathExtension().lastPathComponent.prefix(100)), instrument: .sample,
                              samplePath: url.path, colorIndex: project.tracks.count % 8)
            edit { $0.tracks.append(track) }; selectedTrackID = track.id
        }
        statusMessage = "Imported \(url.lastPathComponent) · C4 plays the original pitch"
    }

    func exportWAV() {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.title = "Export \(mode.rawValue.capitalized) as WAV"
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "\(project.name)-\(mode.rawValue).wav"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = project, playbackMode = mode
        isExporting = true; statusMessage = "Rendering \(playbackMode.rawValue) to WAV…"
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    let audio = try AudioRenderer.render(project: snapshot, mode: playbackMode)
                    try AudioRenderer.writeWAV(audio, to: url)
                }.value
                self?.statusMessage = "Exported \(url.lastPathComponent) · 48 kHz stereo"
            } catch { self?.show(error) }
            self?.isExporting = false
        }
    }

    func confirmDiscard() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(project.name)?"
        alert.informativeText = "Your latest edits have not been saved."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: saveProject(); return !isDirty
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        statusMessage = "\(error.localizedDescription)"
    }
}
