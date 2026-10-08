import AVFoundation
import Foundation
import XCTest
import VLCore
@testable import VLAudio

final class AudioRendererTests: XCTestCase {
    private let rate = 8_000.0

    private func project(_ instrument: InstrumentKind, beat: Double = 0,
                         duration: Double = 0.5, pitch: Int = 60, velocity: Double = 0.8) -> VLProject {
        let track = Track(name: instrument.title, instrument: instrument,
                          notes: [NoteEvent(beat: beat, duration: duration, midiNote: pitch, velocity: velocity)],
                          mixer: MixerSettings(volume: 1))
        return VLProject(tempo: 120, tracks: [track], master: MasterSettings(volume: 1))
    }

    private func energy(_ samples: ArraySlice<Float>) -> Double {
        samples.reduce(0) { $0 + Double($1 * $1) }
    }

    func testEveryOriginalInstrumentProducesFiniteDistinctAudio() throws {
        var fingerprints = Set<[Float]>()
        for kind in [InstrumentKind.kick, .snare, .hat, .bass, .synth] {
            let audio = try AudioRenderer.render(project: project(kind), sampleRate: rate)
            XCTAssertEqual(audio.frameCount, 16_000)
            XCTAssertEqual(audio.duration, 2, accuracy: 0.0001)
            XCTAssertTrue(audio.left.allSatisfy { $0.isFinite && abs($0) <= 1 })
            let attackRMS = sqrt(energy(audio.left[0..<640]) / 640)
            XCTAssertGreaterThan(attackRMS, 0.005, "\(kind) must have an audible attack")
            XCTAssertGreaterThan(audio.left.prefix(4_000).map { abs($0) }.max() ?? 0, 0.015)
            fingerprints.insert(Array(audio.left.prefix(128)))
        }
        XCTAssertEqual(fingerprints.count, 5, "The five voices must use different synthesis")
    }

    func testRebuiltOscillatorUsesMIDIPitchAndPersistsInProjects() throws {
        let song = project(.threeOsc, duration: 2, pitch: 69)
        let decoded = try ProjectDocument.decode(ProjectDocument.encode(song))
        XCTAssertEqual(decoded.tracks[0].instrument, .threeOsc)
        let samples = try AudioRenderer.renderTrack(track: song.tracks[0], project: song,
                                                    mode: .pattern, sampleRate: rate)
        XCTAssertTrue(samples.allSatisfy(\.isFinite))
        let window = samples[800..<4_800]
        func magnitude(_ frequency: Double) -> Double {
            var real = 0.0, imaginary = 0.0
            for (index, sample) in window.enumerated() {
                let phase = 2 * Double.pi * frequency * Double(index) / rate
                real += Double(sample) * cos(phase)
                imaginary += Double(sample) * sin(phase)
            }
            return hypot(real, imaginary)
        }
        XCTAssertGreaterThan(magnitude(440), 100)
        XCTAssertGreaterThan(magnitude(440), 3 * magnitude(220))
        XCTAssertGreaterThan(magnitude(440), 3 * magnitude(880))
        XCTAssertGreaterThan(magnitude(440), 20 * magnitude(444))
    }

    func testOverlappingValidClipsRejectExcessiveNoteExpansion() throws {
        let track = Track(name: "Dense pattern", instrument: .synth,
                          notes: (0..<4_096).map { _ in NoteEvent(beat: 0, duration: 0.0625) })
        let clips = (0..<256).map { _ in ArrangementClip(trackID: track.id, startBar: 0, lengthBars: 16) }
        let song = VLProject(tempo: 240, arrangementBars: 16, tracks: [track], clips: clips)
        // Valid document limits would otherwise expand to16,777,216 records,
        // despite producing only128,000 output frames at this sample rate.
        try song.validated()
        XCTAssertThrowsError(try AudioRenderer.render(project: song, mode: .song, sampleRate: rate)) { error in
            guard case AudioRenderError.renderTooLarge = error else {
                XCTFail("Expected excessive expansion to be rejected, got \(error)")
                return
            }
        }
    }

    func testRebuiltOscillatorKeepsConcurrentRatesAndVoicesIndependent() async throws {
        let requests = [(8_000.0, 60), (44_100.0, 69), (48_000.0, 72), (96_000.0, 81)]
        let expected = try requests.map { sampleRate, pitch -> [Float] in
            let song = project(.threeOsc, duration: 0.25, pitch: pitch)
            return try AudioRenderer.renderTrack(track: song.tracks[0], project: song,
                                                 mode: .pattern, sampleRate: sampleRate)
        }
        let songs = requests.map { project(.threeOsc, duration: 0.25, pitch: $0.1) }
        try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            for index in requests.indices {
                let sampleRate = requests[index].0, song = songs[index]
                group.addTask {
                    (index, try AudioRenderer.renderTrack(track: song.tracks[0], project: song,
                                                          mode: .pattern, sampleRate: sampleRate))
                }
            }
            for try await (index, samples) in group { XCTAssertEqual(samples, expected[index]) }
        }
    }

    func testNoteStartsAtItsBeatAndVelocityScalesEnergy() throws {
        let loudProject = project(.kick, beat: 1, velocity: 0.8)
        let loud = try AudioRenderer.renderTrack(track: loudProject.tracks[0], project: loudProject,
                                                 mode: .pattern, sampleRate: rate)
        let quietProject = project(.kick, beat: 1, velocity: 0.4)
        let quiet = try AudioRenderer.renderTrack(track: quietProject.tracks[0], project: quietProject,
                                                  mode: .pattern, sampleRate: rate)
        XCTAssertEqual(energy(loud[0..<4_000]), 0, accuracy: 0.000001)
        XCTAssertGreaterThan(energy(loud[4_000..<4_800]), 1)
        XCTAssertEqual(energy(quiet[4_000..<8_000]) / energy(loud[4_000..<8_000]), 0.25, accuracy: 0.00001)
    }

    func testPitchedNoteLengthControlsGateAndRelease() throws {
        let shortProject = project(.bass, duration: 0.25, pitch: 36)
        let longProject = project(.bass, duration: 2, pitch: 36)
        let short = try AudioRenderer.render(project: shortProject, sampleRate: rate)
        let long = try AudioRenderer.render(project: longProject, sampleRate: rate)
        XCTAssertEqual(energy(short.left[3_200..<6_400]), 0, accuracy: 0.000001)
        XCTAssertGreaterThan(energy(long.left[3_200..<6_400]), 10)
    }

    func testSongUsesClipPlacementAndRepeatsThePatternInsideClip() throws {
        var song = project(.kick)
        song.arrangementBars = 4
        song.clips = [ArrangementClip(trackID: song.tracks[0].id, startBar: 1, lengthBars: 2)]
        let audio = try AudioRenderer.render(project: song, mode: .song, sampleRate: rate)
        XCTAssertEqual(audio.frameCount, 64_000)
        XCTAssertEqual(energy(audio.left[0..<16_000]), 0, accuracy: 0.000001)
        XCTAssertGreaterThan(energy(audio.left[16_000..<20_000]), 1)
        XCTAssertGreaterThan(energy(audio.left[32_000..<36_000]), 1)
        XCTAssertEqual(energy(audio.left[48_000..<64_000]), 0, accuracy: 0.000001)
        song.clips = []
        let silent = try AudioRenderer.render(project: song, mode: .song, sampleRate: rate)
        XCTAssertEqual(energy(silent.left[...]), 0)
    }

    func testPatternReleaseWrapsAcrossLoopBoundary() throws {
        let loop = project(.kick, beat: 3.75, duration: 0.25)
        let audio = try AudioRenderer.render(project: loop, sampleRate: rate)
        XCTAssertGreaterThan(energy(audio.left[0..<1_500]), 0.01)
        XCTAssertGreaterThan(energy(audio.left[15_000..<16_000]), 1)
        XCTAssertEqual(energy(audio.left[6_000..<10_000]), 0, accuracy: 0.000001)
    }

    func testWAVExportIsStereoPCMWithExpectedDurationAndCanReplaceExistingExport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("groove.wav")
        let audio = try AudioRenderer.render(project: project(.synth), sampleRate: rate)
        try AudioRenderer.writeWAV(audio, to: url)
        try AudioRenderer.writeWAV(audio, to: url)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.channelCount, 2)
        XCTAssertEqual(file.fileFormat.sampleRate, rate)
        XCTAssertEqual(Int(file.length), audio.frameCount)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let data = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertGreaterThan(abs(data[0][80]), 0.001)
        XCTAssertEqual(Double(data[0][80]), Double(audio.left[80]), accuracy: 1 / 32_767)
    }

    func testUserSampleIsDecodedResampledAndPitchChangesPlaybackLength() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("original.wav")
        let source = (0..<3_200).map { Float(sin(Double($0) / rate * 440 * 2 * .pi) * 0.4) }
        try AudioRenderer.writeWAV(StereoBuffer(left: source, right: source, sampleRate: rate), to: url)
        var sampleProject = project(.sample, duration: 2, pitch: 60)
        sampleProject.tracks[0].samplePath = url.path
        let normal = try AudioRenderer.render(project: sampleProject, sampleRate: 16_000)
        XCTAssertGreaterThan(energy(normal.left[200..<3_000]), 1)
        XCTAssertGreaterThan(energy(normal.left[4_000..<6_000]), 1)
        XCTAssertEqual(energy(normal.left[6_800..<10_000]), 0, accuracy: 0.000001)
        sampleProject.tracks[0].notes[0].midiNote = 72
        let octave = try AudioRenderer.render(project: sampleProject, sampleRate: 16_000)
        XCTAssertGreaterThan(energy(octave.left[200..<2_500]), 1)
        XCTAssertEqual(energy(octave.left[3_400..<6_000]), 0, accuracy: 0.000001)
    }

    func testMissingSampleAndMalformedProjectsProduceActionableErrors() throws {
        var missing = project(.sample)
        missing.tracks[0].samplePath = "/tmp/vl-no-such-sample-\(UUID().uuidString).wav"
        XCTAssertThrowsError(try AudioRenderer.render(project: missing, sampleRate: rate)) { error in
            XCTAssertTrue(error.localizedDescription.contains("missing"))
        }
        var invalid = project(.synth)
        invalid.tempo = .nan
        XCTAssertThrowsError(try AudioRenderer.render(project: invalid, sampleRate: rate))
        XCTAssertThrowsError(try AudioRenderer.render(project: project(.synth), sampleRate: .infinity))
        XCTAssertThrowsError(try AudioRenderer.writeWAV(StereoBuffer(left: [.nan], right: [0], sampleRate: rate),
                                                       to: URL(fileURLWithPath: "/tmp/vl-invalid.wav")))
    }

    func testSilentProjectStillHasAPlayableDuration() throws {
        let audio = try AudioRenderer.render(project: VLProject(), sampleRate: rate)
        XCTAssertEqual(audio.frameCount, 16_000)
        XCTAssertEqual(energy(audio.left[...]), 0)
    }
}

final class AudioEngineTests: XCTestCase {
    @MainActor
    func testStopWinsAgainstAnInFlightRender() async throws {
        let engine = VLAudioEngine()
        var track = Track(name: "Bass", instrument: .bass)
        for step in 0..<64 {
            track.notes.append(NoteEvent(beat: Double(step) * 0.25, duration: 0.25, midiNote: 36 + step % 12))
        }
        let project = VLProject(tempo: 40, patternBars: 4, tracks: [track])
        let pending = Task { @MainActor in try await engine.play(project: project, mode: .pattern) }
        for _ in 0..<5 { await Task.yield() }
        engine.stop()
        try await pending.value
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.currentBeat, 0)
        XCTAssertEqual(engine.levels.left, 0)
    }
}
