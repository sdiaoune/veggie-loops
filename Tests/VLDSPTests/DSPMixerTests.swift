import XCTest
import VLCore
@testable import VLDSP

final class DSPMixerTests: XCTestCase {
    private let unity = MasterSettings(volume: 1, delayTimeBeats: 1, delayFeedback: 0)

    func testEqualPowerPanPreservesEnergyAndHardPanIsSilentOnOtherSide() {
        let input: [Float] = [0.25, -0.25, 0.125]
        let center = DSPMixer.mix(monoBuffers: [input], settings: [MixerSettings(volume: 1)],
                                  master: unity, sampleRate: 48_000, tempo: 120)
        for frame in input.indices {
            XCTAssertEqual(center.left[frame], center.right[frame], accuracy: 0.000001)
            XCTAssertEqual(center.left[frame] * center.left[frame] + center.right[frame] * center.right[frame],
                           input[frame] * input[frame], accuracy: 0.000001)
        }
        for pan in [-1.0, 1.0] {
            let output = DSPMixer.mix(monoBuffers: [input], settings: [MixerSettings(volume: 1, pan: pan)],
                                      master: unity, sampleRate: 48_000, tempo: 120)
            XCTAssertEqual(pan < 0 ? output.left : output.right, input)
            XCTAssertTrue((pan < 0 ? output.right : output.left).allSatisfy { $0 == 0 })
        }
    }

    func testSoloExcludesOtherTracksAndMuteOverridesSolo() {
        let input: [Float] = [0.2, 0.1]
        let output = DSPMixer.mix(monoBuffers: [input, input, input], settings: [
            MixerSettings(volume: 1, pan: -1, solo: true),
            MixerSettings(volume: 1, pan: 1),
            MixerSettings(volume: 1, pan: 1, muted: true, solo: true)
        ], master: unity, sampleRate: 48_000, tempo: 120)
        XCTAssertEqual(output.left, input)
        XCTAssertEqual(output.right, [0, 0])
    }

    func testMutedSoloDoesNotSilenceAnOtherwiseAudibleMix() {
        let output = DSPMixer.mix(monoBuffers: [[0.3], [0.2]], settings: [
            MixerSettings(volume: 1, pan: -1, muted: true, solo: true),
            MixerSettings(volume: 1, pan: 1)
        ], master: unity, sampleRate: 48_000, tempo: 120)
        XCTAssertEqual(output.left, [0])
        XCTAssertEqual(output.right, [0.2])
    }

    func testTempoDelayAndCrossFeedbackProduceMeasuredEchoes() {
        var impulse = [Float](repeating: 0, count: 301)
        impulse[0] = 0.2
        let output = DSPMixer.mix(monoBuffers: [impulse],
            settings: [MixerSettings(volume: 1, pan: -1, delaySend: 1)],
            master: MasterSettings(volume: 1, delayTimeBeats: 1, delayFeedback: 0.5),
            sampleRate: 100, tempo: 60)
        XCTAssertEqual(output.frameCount, 301)
        XCTAssertEqual(output.left[0], 0.2, accuracy: 0.000001)
        XCTAssertEqual(output.left[100], 0.2, accuracy: 0.000001)
        XCTAssertEqual(output.right[200], 0.1, accuracy: 0.000001)
        XCTAssertEqual(output.left[300], 0.05, accuracy: 0.000001)
        XCTAssertEqual(output.right[100], 0)
        XCTAssertEqual(output.left[99], 0)

        let faster = DSPMixer.mix(monoBuffers: [impulse],
            settings: [MixerSettings(volume: 1, pan: -1, delaySend: 1)],
            master: unity, sampleRate: 100, tempo: 120)
        XCTAssertEqual(faster.left[50], 0.2, accuracy: 0.000001)
        XCTAssertEqual(faster.left[100], 0)
    }

    func testLowpassAttenuatesHighFrequenciesAndDriveChangesTimbre() {
        let alternating: [Float] = (0..<4096).map { $0.isMultiple(of: 2) ? 0.2 : -0.2 }
        let filtered = DSPMixer.mix(monoBuffers: [alternating],
            settings: [MixerSettings(volume: 1, pan: -1, cutoffHz: 500)],
            master: unity, sampleRate: 48_000, tempo: 120)
        XCTAssertLessThan(rms(Array(filtered.left.dropFirst(100))), 0.01)

        let sine = (0..<4096).map { Float(0.1 * sin(Double($0) * 2 * .pi * 440 / 48_000)) }
        let driven = DSPMixer.mix(monoBuffers: [sine],
            settings: [MixerSettings(volume: 1, pan: -1, drive: 1)],
            master: unity, sampleRate: 48_000, tempo: 120)
        XCTAssertGreaterThan(rms(driven.left), rms(sine) * 5)
        XCTAssertTrue(driven.left.allSatisfy { $0.isFinite && abs($0) <= 1 })
    }

    func testInvalidParametersAndSamplesAlwaysProduceFiniteBoundedAudio() {
        let signal: [Float] = [.nan, .infinity, -.infinity, Float.greatestFiniteMagnitude, -10, 0.5]
        let output = DSPMixer.mix(monoBuffers: [signal, signal], settings: [
            MixerSettings(volume: .infinity, pan: .nan, cutoffHz: -.infinity, delaySend: .nan, drive: .infinity),
            MixerSettings(volume: 2, pan: 1, cutoffHz: 20_000, drive: 1)
        ], master: MasterSettings(volume: .nan, delayTimeBeats: .infinity, delayFeedback: .nan),
        sampleRate: .nan, tempo: .nan)
        XCTAssertEqual(output.sampleRate, 48_000)
        XCTAssertEqual(output.frameCount, signal.count)
        XCTAssertTrue((output.left + output.right).allSatisfy { $0.isFinite && abs($0) <= 1 })
        XCTAssertEqual(Array(output.left.prefix(3)), [0, 0, 0])
    }

    func testMasterGainAndSilence() {
        let output = DSPMixer.mix(monoBuffers: [[0.2]], settings: [MixerSettings(volume: 1, pan: -1)],
            master: MasterSettings(volume: 0.5), sampleRate: 48_000, tempo: 120)
        XCTAssertEqual(output.left[0], 0.1, accuracy: 0.000001)
        let silent = DSPMixer.mix(monoBuffers: [[1, 1]], settings: [MixerSettings(volume: 0, delaySend: 1)],
            master: unity, sampleRate: 48_000, tempo: 120)
        XCTAssertEqual(silent.left, [0, 0])
        XCTAssertEqual(silent.right, [0, 0])
    }

    func testEmptyAndUnequalBuffersAreHandledWithoutOutOfBoundsAccess() {
        let empty = DSPMixer.mix(monoBuffers: [], settings: [], master: unity, sampleRate: 48_000, tempo: 120)
        XCTAssertEqual(empty.frameCount, 0)
        let unequal = DSPMixer.mix(monoBuffers: [[0.2], [0, 0.1, 0]],
            settings: [MixerSettings(volume: 1, pan: -1), MixerSettings(volume: 1, pan: 1)],
            master: unity, sampleRate: 48_000, tempo: 120)
        XCTAssertEqual(unequal.left, [0.2, 0, 0])
        XCTAssertEqual(unequal.right, [0, 0.1, 0])
    }

    private func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count)))
    }
}
