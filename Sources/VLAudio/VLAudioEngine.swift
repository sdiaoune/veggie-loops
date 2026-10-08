import AVFoundation
import Foundation
import VLCore

/// A main-thread transport backed by pre-rendered PCM and native player nodes.
/// Rendering tasks are revision guarded: Stop and later edits always win.
@MainActor
public final class VLAudioEngine {
    public private(set) var isPlaying = false
    public private(set) var currentBeat: Double = 0
    public private(set) var levels = AudioLevels()
    public let sampleRate: Double = 48_000
    public var onFailure: ((Error) -> Void)?

    private let engine = AVAudioEngine()
    private let musicPlayer = AVAudioPlayerNode()
    private let previewPlayer = AVAudioPlayerNode()
    private var renderTask: Task<PreparedAudio, Error>?
    private var previewTask: Task<PreparedAudio, Error>?
    private var revision: UInt64 = 0
    private var previewRevision: UInt64 = 0
    private var prepared: PreparedAudio?
    private var preview: PreparedAudio?
    private var playbackBuffer: AVAudioPCMBuffer?
    private var previewBuffer: AVAudioPCMBuffer?
    private var frameOffset = 0
    private var playbackTempo: Double = 120
    private var playbackBeats: Double = 4
    private var playbackStarted: TimeInterval = 0
    private var previewStarted: TimeInterval = 0
    private var timer: Timer?
    private var configurationObserver: NSObjectProtocol?

    public init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(musicPlayer)
        engine.attach(previewPlayer)
        engine.connect(musicPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(previewPlayer, to: engine.mainMixerNode, format: format)
        // Rendered master gain is shared by playback and WAV export.
        engine.mainMixerNode.outputVolume = 1
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recoverConfiguration() }
        }
    }

    public func play(project: VLProject, mode: PlaybackMode) async throws {
        revision &+= 1
        let token = revision
        renderTask?.cancel()
        let rate = sampleRate
        let task = Task.detached(priority: .userInitiated) {
            try AudioRenderer.prepare(project: project, mode: mode, sampleRate: rate)
        }
        renderTask = task
        let rendered: PreparedAudio
        do {
            rendered = try await withTaskCancellationHandler(operation: { try await task.value },
                                                              onCancel: { task.cancel() })
        }
        catch {
            if token != revision || task.isCancelled { return }
            renderTask = nil
            throw error
        }
        guard token == revision, !task.isCancelled, !Task.isCancelled else { return }
        renderTask = nil
        try start(rendered, project: project, mode: mode, atBeat: 0)
    }

    public func refresh(project: VLProject, mode: PlaybackMode) async throws {
        guard isPlaying else { return }
        revision &+= 1
        let token = revision
        renderTask?.cancel()
        let rate = sampleRate
        let task = Task.detached(priority: .userInitiated) {
            try AudioRenderer.prepare(project: project, mode: mode, sampleRate: rate)
        }
        renderTask = task
        let rendered: PreparedAudio
        do {
            rendered = try await withTaskCancellationHandler(operation: { try await task.value },
                                                              onCancel: { task.cancel() })
        }
        catch {
            if token != revision || task.isCancelled { return }
            renderTask = nil
            throw error
        }
        guard token == revision, !task.isCancelled, !Task.isCancelled, isPlaying else { return }
        renderTask = nil
        tick()
        try start(rendered, project: project, mode: mode,
                  atBeat: currentBeat.truncatingRemainder(dividingBy: project.lengthBeats(for: mode)))
    }

    public func stop() {
        revision &+= 1
        previewRevision &+= 1
        renderTask?.cancel()
        previewTask?.cancel()
        renderTask = nil
        previewTask = nil
        musicPlayer.stop()
        previewPlayer.stop()
        engine.pause()
        isPlaying = false
        currentBeat = 0
        levels = AudioLevels()
        prepared = nil
        preview = nil
        playbackBuffer = nil
        previewBuffer = nil
        timer?.invalidate()
        timer = nil
    }

    public func audition(track: Track, midiNote: Int) async throws {
        previewRevision &+= 1
        let token = previewRevision
        previewTask?.cancel()
        var voice = track
        voice.notes = [NoteEvent(beat: 0, duration: 2, midiNote: min(127, max(0, midiNote)), velocity: 0.9)]
        // An audition must remain audible when its track is muted or another track is soloed.
        voice.mixer.muted = false
        voice.mixer.solo = false
        let project = VLProject(tempo: 120, tracks: [voice], master: MasterSettings(volume: 0.72))
        let rate = sampleRate
        let task = Task.detached(priority: .userInitiated) {
            try AudioRenderer.prepare(project: project, mode: .pattern, sampleRate: rate)
        }
        previewTask = task
        let rendered: PreparedAudio
        do {
            rendered = try await withTaskCancellationHandler(operation: { try await task.value },
                                                              onCancel: { task.cancel() })
        }
        catch {
            if token != previewRevision || task.isCancelled { return }
            previewTask = nil
            throw error
        }
        guard token == previewRevision, !task.isCancelled, !Task.isCancelled else { return }
        previewTask = nil
        let buffer = try pcmBuffer(rendered.audio, startingFrame: 0)
        try ensureRunning()
        previewPlayer.stop()
        previewPlayer.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, token == self.previewRevision else { return }
                self.preview = nil
                self.previewBuffer = nil
                if !self.isPlaying {
                    self.levels = AudioLevels()
                    self.timer?.invalidate()
                    self.timer = nil
                    self.engine.pause()
                }
            }
        }
        preview = rendered
        previewBuffer = buffer
        previewStarted = ProcessInfo.processInfo.systemUptime
        previewPlayer.play()
        startTimer()
        tick()
    }

    private func start(_ rendered: PreparedAudio, project: VLProject,
                       mode: PlaybackMode, atBeat: Double) throws {
        guard rendered.audio.frameCount > 0 else { throw AudioRenderError.invalidBuffer }
        let startFrame = min(rendered.audio.frameCount - 1,
                             max(0, Int((atBeat * 60 / project.tempo * sampleRate).rounded())))
        let buffer = try pcmBuffer(rendered.audio, startingFrame: startFrame)
        try ensureRunning()
        musicPlayer.stop()
        musicPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        prepared = rendered
        playbackBuffer = buffer
        playbackTempo = project.tempo
        playbackBeats = project.lengthBeats(for: mode)
        frameOffset = startFrame
        playbackStarted = ProcessInfo.processInfo.systemUptime
        currentBeat = atBeat
        isPlaying = true
        musicPlayer.play()
        startTimer()
        tick()
    }

    private func ensureRunning() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func recoverConfiguration() {
        guard !engine.isRunning else { return }
        guard isPlaying, let prepared else {
            if preview != nil {
                previewRevision &+= 1
                previewPlayer.stop()
                preview = nil
                previewBuffer = nil
                levels = AudioLevels()
                timer?.invalidate()
                timer = nil
            }
            return
        }
        // Device changes reset player clocks. Musical phase comes from the
        // monotonic fallback until the replacement device begins rendering.
        let elapsed = max(0, Int((ProcessInfo.processInfo.systemUptime - playbackStarted) * sampleRate))
        let frame = (frameOffset + elapsed) % prepared.audio.frameCount
        do {
            let buffer = try pcmBuffer(prepared.audio, startingFrame: frame)
            try ensureRunning()
            musicPlayer.stop()
            musicPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            playbackBuffer = buffer
            frameOffset = frame
            playbackStarted = ProcessInfo.processInfo.systemUptime
            musicPlayer.play()
            tick()
        } catch {
            stop()
            onFailure?(error)
        }
    }

    private func pcmBuffer(_ audio: StereoBuffer, startingFrame: Int) throws -> AVAudioPCMBuffer {
        guard audio.frameCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.frameCount)),
              let channels = buffer.floatChannelData else { throw AudioRenderError.invalidBuffer }
        buffer.frameLength = AVAudioFrameCount(audio.frameCount)
        let offset = startingFrame % audio.frameCount
        // Rotate a loop when refreshing so the current musical beat keeps playing.
        // The copy happens on the main thread, never in the audio callback.
        for (index, samples) in [audio.left, audio.right].enumerated() {
            samples.withUnsafeBufferPointer { source in
                let remaining = audio.frameCount - offset
                channels[index].update(from: source.baseAddress!.advanced(by: offset), count: remaining)
                if offset > 0 {
                    channels[index].advanced(by: remaining).update(from: source.baseAddress!, count: offset)
                }
            }
        }
        return buffer
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func elapsedFrames(player: AVAudioPlayerNode, started: TimeInterval) -> Int {
        if let time = player.lastRenderTime, let playerTime = player.playerTime(forNodeTime: time) {
            return max(0, Int(Double(playerTime.sampleTime) * sampleRate / playerTime.sampleRate))
        }
        return max(0, Int((ProcessInfo.processInfo.systemUptime - started) * sampleRate))
    }

    private func tick() {
        var output = AudioLevels()
        if isPlaying, let prepared {
            let frame = (frameOffset + elapsedFrames(player: musicPlayer, started: playbackStarted)) % prepared.audio.frameCount
            currentBeat = min(playbackBeats, Double(frame) / sampleRate * playbackTempo / 60)
            output = prepared.levels(at: frame)
        }
        if let preview {
            let frame = elapsedFrames(player: previewPlayer, started: previewStarted)
            if frame < preview.audio.frameCount {
                let previewLevels = preview.levels(at: frame)
                output.left = min(1, output.left + previewLevels.left)
                output.right = min(1, output.right + previewLevels.right)
                for (id, peak) in previewLevels.tracks { output.tracks[id] = max(output.tracks[id] ?? 0, peak) }
            }
        }
        levels = output
    }
}
