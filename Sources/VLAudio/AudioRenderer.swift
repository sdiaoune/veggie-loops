import AVFoundation
import Foundation
import VLCore
import VLDSP
import VLNativeDSP

public enum AudioRenderError: LocalizedError {
    case invalidRate
    case renderTooLarge
    case missingSample(String)
    case invalidSample(String)
    case sampleTooLarge(String)
    case invalidBuffer
    case nativeInstrumentFailed

    public var errorDescription: String? {
        switch self {
        case .invalidRate: return "Choose an audio sample rate between 8,000 and 192,000 Hz."
        case .renderTooLarge: return "This render is too large. Reduce the song length, track count, or sample rate."
        case .missingSample(let path): return "The sample ‘\(URL(fileURLWithPath: path).lastPathComponent)’ is missing. Import it again on its track."
        case .invalidSample(let name): return "‘\(name)’ could not be decoded as audio. Try a WAV, AIFF, or MP3 file."
        case .sampleTooLarge(let name): return "‘\(name)’ is too large for a sampler. Import audio under two minutes and 256 MB."
        case .invalidBuffer: return "The rendered audio buffer is empty or invalid."
        case .nativeInstrumentFailed: return "VL 3 Osc could not render this note. Try playing again."
        }
    }
}

/// All synthesis and mixing happens before scheduling a native playback buffer.
/// The device callback is AVAudioPlayerNode's native implementation.
public enum AudioRenderer {
    public static func render(project: VLProject, mode: PlaybackMode = .pattern,
                              sampleRate: Double = 48_000) throws -> StereoBuffer {
        let tracks = try renderTracks(project: project, mode: mode, sampleRate: sampleRate)
        return DSPMixer.mix(monoBuffers: tracks, settings: project.tracks.map(\.mixer),
                            master: project.master, sampleRate: sampleRate, tempo: project.tempo)
    }

    public static func renderTrack(track: Track, project: VLProject, mode: PlaybackMode,
                                   sampleRate: Double) throws -> [Float] {
        try project.validated()
        var checked = project
        checked.tracks = [track]
        checked.clips = project.clips.filter { $0.trackID == track.id }
        try checked.validated()
        let frameCount = try checkedFrameCount(project: project, mode: mode, sampleRate: sampleRate)
        return try synthesize(track: track, project: project, mode: mode,
                              sampleRate: sampleRate, frameCount: frameCount)
    }

    public static func writeWAV(_ audio: StereoBuffer, to url: URL) throws {
        guard audio.sampleRate.isFinite, (8_000...192_000).contains(audio.sampleRate),
              audio.left.count == audio.right.count, audio.frameCount > 0,
              audio.frameCount <= 100_000_000,
              audio.left.allSatisfy({ $0.isFinite }), audio.right.allSatisfy({ $0.isFinite }) else {
            throw AudioRenderError.invalidBuffer
        }
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".vl-export-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            let file = try AVAudioFile(forWriting: temporary, settings: settings,
                                       commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let chunk = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536),
                  let channels = chunk.floatChannelData else { throw AudioRenderError.invalidBuffer }
            var offset = 0
            while offset < audio.frameCount {
                try Task.checkCancellation()
                let count = min(65_536, audio.frameCount - offset)
                chunk.frameLength = AVAudioFrameCount(count)
                audio.left.withUnsafeBufferPointer { source in
                    channels[0].update(from: source.baseAddress!.advanced(by: offset), count: count)
                }
                audio.right.withUnsafeBufferPointer { source in
                    channels[1].update(from: source.baseAddress!.advanced(by: offset), count: count)
                }
                try file.write(from: chunk)
                offset += count
            }
        }
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }

    static func prepare(project: VLProject, mode: PlaybackMode, sampleRate: Double,
                        looping: Bool = false) throws -> PreparedAudio {
        let mono = try renderTracks(project: project, mode: mode, sampleRate: sampleRate)
        try Task.checkCancellation()
        let audio = DSPMixer.mix(monoBuffers: mono, settings: project.tracks.map(\.mixer),
                                 master: project.master, sampleRate: sampleRate, tempo: project.tempo,
                                 looping: looping)
        let size = 1_024
        let left = peakWindows(audio.left, size: size)
        let right = peakWindows(audio.right, size: size)
        let anySolo = project.tracks.contains { $0.mixer.solo && !$0.mixer.muted }
        var trackPeaks: [UUID: [Double]] = [:]
        for (index, track) in project.tracks.enumerated() {
            let audible = !track.mixer.muted && (!anySolo || track.mixer.solo)
            let gain = audible ? track.mixer.volume : 0
            trackPeaks[track.id] = peakWindows(mono[index], size: size).map { min(1, $0 * gain) }
        }
        return PreparedAudio(audio: audio, meterWindow: size, leftPeaks: left,
                             rightPeaks: right, trackPeaks: trackPeaks)
    }

    private static func renderTracks(project: VLProject, mode: PlaybackMode,
                                     sampleRate: Double) throws -> [[Float]] {
        try project.validated()
        let frameCount = try checkedFrameCount(project: project, mode: mode, sampleRate: sampleRate)
        if project.tracks.isEmpty { return [[Float](repeating: 0, count: frameCount)] }
        return try project.tracks.map { track in
            try Task.checkCancellation()
            return try synthesize(track: track, project: project, mode: mode,
                                  sampleRate: sampleRate, frameCount: frameCount)
        }
    }

    private static func checkedFrameCount(project: VLProject, mode: PlaybackMode,
                                          sampleRate: Double) throws -> Int {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate) else { throw AudioRenderError.invalidRate }
        let frames = project.lengthBeats(for: mode) * 60 / project.tempo * sampleRate
        guard frames >= 1, frames <= 20_000_000,
              frames * Double(max(1, project.tracks.count)) <= 100_000_000 else {
            throw AudioRenderError.renderTooLarge
        }
        return Int(frames.rounded())
    }

    private struct Placement {
        var note: NoteEvent
        var beat: Double
        var endBeat: Double
    }

    private static func placements(track: Track, project: VLProject, mode: PlaybackMode) throws -> [Placement] {
        try Task.checkCancellation()
        if mode == .pattern {
            return track.notes.map { Placement(note: $0, beat: $0.beat, endBeat: project.patternBeats) }
        }
        var result: [Placement] = []
        for clip in project.clips where clip.trackID == track.id {
            let start = Double(clip.startBar * 4)
            let end = Double((clip.startBar + clip.lengthBars) * 4)
            var repeatBeat = start
            while repeatBeat < end {
                try Task.checkCancellation()
                for note in track.notes where repeatBeat + note.beat < end {
                    // Document note/clip limits do not bound their product:
                    // overlapping clips can repeat millions of placements.
                    // Keep this temporary expansion small before synthesis.
                    guard result.count < 65_536 else { throw AudioRenderError.renderTooLarge }
                    result.append(Placement(note: note, beat: repeatBeat + note.beat, endBeat: end))
                }
                repeatBeat += project.patternBeats
            }
        }
        return result
    }

    private static func synthesize(track: Track, project: VLProject, mode: PlaybackMode,
                                   sampleRate: Double, frameCount: Int) throws -> [Float] {
        let events = try placements(track: track, project: project, mode: mode)
        var result = [Float](repeating: 0, count: frameCount)
        // Decode once per track. A missing sample is actionable even before placing its first note.
        let sample: DecodedSample?
        if track.instrument == .sample {
            guard let path = track.samplePath else { return result }
            sample = try decodeSample(path: path)
        } else { sample = nil }
        let secondsPerBeat = 60 / project.tempo
        var workFrames: Int64 = 0
        for placement in events {
            try Task.checkCancellation()
            let note = placement.note
            guard note.velocity > 0 else { continue }
            let startFrame = Int((placement.beat * secondsPerBeat * sampleRate).rounded())
            let gateSeconds = min(note.duration, placement.endBeat - placement.beat) * secondsPerBeat
            let frequency = 440 * pow(2, Double(note.midiNote - 69) / 12)
            let voiceSeconds: Double
            switch track.instrument {
            case .kick: voiceSeconds = 0.58
            case .snare: voiceSeconds = 0.27
            case .hat: voiceSeconds = 0.14
            case .bass: voiceSeconds = gateSeconds + 0.075
            case .synth: voiceSeconds = gateSeconds + 0.18
            case .threeOsc: voiceSeconds = gateSeconds + 0.12
            case .sample:
                let sourceDuration = sample.map { Double($0.frames.count) / $0.sampleRate } ?? 0
                let ratio = pow(2, Double(note.midiNote - 60) / 12)
                voiceSeconds = min(sourceDuration / ratio, gateSeconds + 0.02)
            }
            let voiceFrames = max(0, Int((voiceSeconds * sampleRate).rounded()))
            workFrames += Int64(voiceFrames)
            guard workFrames <= 200_000_000 else { throw AudioRenderError.renderTooLarge }
            let nativeVoice = track.instrument == .threeOsc
                ? try renderNativeVoice(note: note.midiNote, sampleRate: sampleRate, frames: voiceFrames) : nil
            var seed = UInt32(truncatingIfNeeded: startFrame &* 1_664_525 &+ note.midiNote &* 101_390_4223 &+ 1)
            var previousNoise = 0.0
            let clipEndFrame = Int((placement.endBeat * secondsPerBeat * sampleRate).rounded())
            for localFrame in 0..<voiceFrames {
                if localFrame & 16_383 == 0 { try Task.checkCancellation() }
                var destination = startFrame + localFrame
                if mode == .pattern {
                    destination %= frameCount
                } else if destination >= min(frameCount, clipEndFrame) {
                    break
                }
                guard destination >= 0, destination < frameCount else { continue }
                let time = Double(localFrame) / sampleRate
                let value: Double
                switch track.instrument {
                case .kick:
                    // Integrate a falling frequency to avoid a phase discontinuity during the pitch sweep.
                    let phase = 2 * Double.pi * (47 * time + 108 * 0.023 * (1 - exp(-time / 0.023)))
                    let body = sin(phase) * exp(-time * 8.7)
                    let click = noise(&seed) * exp(-time * 380) * 0.12
                    value = (body * 0.88 + click) * min(1, time / 0.001)
                case .snare:
                    let white = noise(&seed)
                    let high = white - previousNoise * 0.72
                    previousNoise = white
                    let body = sin(2 * Double.pi * 185 * time) * exp(-time * 27) * 0.23
                    value = (high * exp(-time * 20) * 0.38 + body) * min(1, time / 0.001)
                case .hat:
                    let white = noise(&seed)
                    let high = white - previousNoise * 0.95
                    previousNoise = white
                    let metallic = sin(2 * Double.pi * 6_103 * time) * sin(2 * Double.pi * 8_077 * time)
                    value = (high * 0.11 + metallic * 0.06) * exp(-time * 42) * min(1, time / 0.0005)
                case .bass:
                    let fundamental = sin(2 * Double.pi * frequency * time)
                    let overtone = frequency * 2 < sampleRate / 2 ? sin(4 * Double.pi * frequency * time) : 0
                    let envelope = min(1, time / 0.008) * exp(-time * 0.7)
                        * release(time: time, gate: gateSeconds, length: 0.075)
                    value = tanh((fundamental * 0.66 + overtone * 0.18) * 1.3) * envelope * 0.51
                case .synth:
                    let phase = frequency * time
                    let triangle = 2 / Double.pi * asin(sin(2 * Double.pi * phase))
                    let second = frequency * 2 < sampleRate / 2 ? sin(4 * Double.pi * phase + 0.18) : 0
                    let envelope = min(1, time / 0.009) * (0.55 + 0.45 * exp(-time * 3.8))
                        * release(time: time, gate: gateSeconds, length: 0.18)
                    value = (triangle * 0.35 + second * 0.09) * envelope
                case .threeOsc:
                    let envelope = min(1, time / 0.008)
                        * release(time: time, gate: gateSeconds, length: 0.12)
                    value = Double(nativeVoice![localFrame]) * envelope * 0.5
                case .sample:
                    guard let sample, !sample.frames.isEmpty else { continue }
                    let ratio = pow(2, Double(note.midiNote - 60) / 12)
                    let source = time * sample.sampleRate * ratio
                    let index = Int(source)
                    guard index < sample.frames.count else { continue }
                    let fraction = source - Double(index)
                    let first = Double(sample.frames[index])
                    let second = Double(sample.frames[min(index + 1, sample.frames.count - 1)])
                    let sourceTail = max(0, min(1, (voiceSeconds - time) / 0.004))
                    value = (first + (second - first) * fraction) * min(1, time / 0.001)
                        * release(time: time, gate: gateSeconds, length: 0.02) * sourceTail
                }
                var fade = 1.0
                if mode == .song {
                    // A clip ending mid-release has a short fade rather than a click.
                    fade = min(1, Double(clipEndFrame - destination) / max(1, sampleRate * 0.003))
                }
                result[destination] += Float(value * note.velocity * fade)
            }
        }
        return result
    }

    private static func renderNativeVoice(note: Int, sampleRate: Double, frames: Int) throws -> [Float] {
        guard let voice = vl_native_oscillator_create(Int32(note), Int32(sampleRate.rounded())) else {
            throw AudioRenderError.nativeInstrumentFailed
        }
        defer { vl_native_oscillator_destroy(voice) }
        var samples = [Float](repeating: 0, count: frames)
        var offset = 0
        while offset < frames {
            try Task.checkCancellation()
            let count = min(1_024, frames - offset)
            let ok = samples.withUnsafeMutableBufferPointer { buffer in
                vl_native_oscillator_render(voice, buffer.baseAddress!.advanced(by: offset), UInt32(count))
            }
            guard ok != 0 else { throw AudioRenderError.nativeInstrumentFailed }
            offset += count
        }
        return samples
    }

    private static func release(time: Double, gate: Double, length: Double) -> Double {
        time <= gate ? 1 : max(0, 1 - (time - gate) / length)
    }

    private static func noise(_ seed: inout UInt32) -> Double {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Double(seed) / Double(UInt32.max) * 2 - 1
    }

    private struct DecodedSample {
        var frames: [Float]
        var sampleRate: Double
    }

    private static func decodeSample(path: String) throws -> DecodedSample {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { throw AudioRenderError.missingSample(path) }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 256_000_000 else { throw AudioRenderError.sampleTooLarge(url.lastPathComponent) }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) }
        catch { throw AudioRenderError.invalidSample(url.lastPathComponent) }
        let format = file.processingFormat
        guard format.sampleRate.isFinite, format.sampleRate > 0, file.length > 0,
              format.channelCount > 0, format.channelCount <= 32 else {
            throw AudioRenderError.invalidSample(url.lastPathComponent)
        }
        guard Double(file.length) / format.sampleRate <= 120,
              file.length <= 24_000_000 else { throw AudioRenderError.sampleTooLarge(url.lastPathComponent) }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536),
              let channels = buffer.floatChannelData else {
            throw AudioRenderError.invalidSample(url.lastPathComponent)
        }
        var mono = [Float]()
        mono.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: min(65_536, AVAudioFrameCount(file.length - file.framePosition)))
            let count = Int(buffer.frameLength)
            guard count > 0 else { break }
            for frame in 0..<count {
                var value: Float = 0
                for channel in 0..<Int(format.channelCount) {
                    let item = channels[channel][frame]
                    if item.isFinite { value += min(1, max(-1, item)) / Float(format.channelCount) }
                }
                mono.append(value)
            }
        }
        guard !mono.isEmpty else { throw AudioRenderError.invalidSample(url.lastPathComponent) }
        return DecodedSample(frames: mono, sampleRate: format.sampleRate)
    }

    private static func peakWindows(_ samples: [Float], size: Int) -> [Double] {
        var result = [Double]()
        result.reserveCapacity((samples.count + size - 1) / size)
        var position = 0
        while position < samples.count {
            let end = min(samples.count, position + size)
            var peak: Float = 0
            for index in position..<end { peak = max(peak, abs(samples[index])) }
            result.append(Double(peak))
            position = end
        }
        return result
    }
}

struct PreparedAudio: Sendable {
    var audio: StereoBuffer
    var meterWindow: Int
    var leftPeaks: [Double]
    var rightPeaks: [Double]
    var trackPeaks: [UUID: [Double]]

    func levels(at frame: Int) -> AudioLevels {
        let index = min(max(0, frame / meterWindow), max(0, leftPeaks.count - 1))
        var tracks: [UUID: Double] = [:]
        for (id, peaks) in trackPeaks { tracks[id] = index < peaks.count ? peaks[index] : 0 }
        return AudioLevels(left: index < leftPeaks.count ? leftPeaks[index] : 0,
                           right: index < rightPeaks.count ? rightPeaks[index] : 0, tracks: tracks)
    }
}
