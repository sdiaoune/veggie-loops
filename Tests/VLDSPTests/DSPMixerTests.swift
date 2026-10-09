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

    func testLoopDelayWrapsLateImpulseEvenWhenDelayExceedsLoop() {
        let input: [Float] = [0, 0, 0, 0.2]
        let settings = [MixerSettings(volume: 1, pan: -1, delaySend: 1)]
        // Five frames of delay on a four-frame periodic signal shifts by one.
        let master = MasterSettings(volume: 1, delayTimeBeats: 1.25, delayFeedback: 0)
        let finite = DSPMixer.mix(monoBuffers: [input], settings: settings,
                                  master: master, sampleRate: 4, tempo: 60)
        let loop = DSPMixer.mix(monoBuffers: [input], settings: settings,
                                master: master, sampleRate: 4, tempo: 60, looping: true)
        XCTAssertEqual(finite.left, input)
        XCTAssertEqual(finite.right, [0, 0, 0, 0])
        XCTAssertEqual(loop.frameCount, input.count)
        XCTAssertEqual(loop.left, [0.2, 0, 0, 0.2])
        XCTAssertEqual(loop.right, [0, 0, 0, 0])
    }

    func testLoopDelayEqualToLoopLengthAddsAnEchoWithoutExtendingOutput() {
        let input: [Float] = [0.2, 0, 0, 0]
        let settings = [MixerSettings(volume: 1, pan: -1, delaySend: 1)]
        let master = MasterSettings(volume: 1, delayTimeBeats: 1, delayFeedback: 0)
        let finite = DSPMixer.mix(monoBuffers: [input], settings: settings,
                                  master: master, sampleRate: 4, tempo: 60)
        let loop = DSPMixer.mix(monoBuffers: [input], settings: settings,
                                master: master, sampleRate: 4, tempo: 60, looping: true)
        XCTAssertEqual(finite.left, input)
        XCTAssertEqual(loop.frameCount, input.count)
        XCTAssertEqual(loop.left, [0.4, 0, 0, 0])
        XCTAssertEqual(loop.right, [0, 0, 0, 0])
    }

    func testLoopDelayCrossFeedbackAlternatesSidesAcrossAnEvenCycle() {
        let input: [Float] = [0.2, 0, 0, 0]
        let output = DSPMixer.mix(monoBuffers: [input],
            settings: [MixerSettings(volume: 1, pan: -1, delaySend: 1)],
            master: MasterSettings(volume: 1, delayTimeBeats: 0.25, delayFeedback: 0.5),
            sampleRate: 4, tempo: 60, looping: true)
        // Repeating echoes sum a geometric series with ratio (1/2)^4.
        let expectedLeft: [Double] = [0.2, 0.2 * 16 / 15, 0, 0.2 * 4 / 15]
        let expectedRight: [Double] = [0.2 * 2 / 15, 0, 0.2 * 8 / 15, 0]
        for frame in input.indices {
            XCTAssertEqual(Double(output.left[frame]), expectedLeft[frame], accuracy: 0.000001)
            XCTAssertEqual(Double(output.right[frame]), expectedRight[frame], accuracy: 0.000001)
        }
    }

    func testLoopDelaySeparatesIndexCyclesAndSolvesOddChannelSwaps() {
        let input: [Float] = [0.2, 0, 0, 0, 0, 0]
        let output = DSPMixer.mix(monoBuffers: [input],
            settings: [MixerSettings(volume: 1, pan: -1, delaySend: 1)],
            master: MasterSettings(volume: 1, delayTimeBeats: 0.25, delayFeedback: 0.5),
            sampleRate: 8, tempo: 60, looping: true)
        // Two-frame advances visit only even frames. Three advances swap sides;
        // the same side returns after six, giving ratio (1/2)^6 and denominator 63.
        let expectedLeft: [Double] = [0.2 + 0.2 * 16 / 63, 0, 0.2 * 64 / 63, 0, 0.2 * 4 / 63, 0]
        let expectedRight: [Double] = [0.2 * 2 / 63, 0, 0.2 * 8 / 63, 0, 0.2 * 32 / 63, 0]
        for frame in input.indices {
            XCTAssertEqual(Double(output.left[frame]), expectedLeft[frame], accuracy: 0.000001)
            XCTAssertEqual(Double(output.right[frame]), expectedRight[frame], accuracy: 0.000001)
        }
    }

    func testLoopDelayRemainsFiniteAtMaximumMixerFeedback() {
        let output = DSPMixer.mix(monoBuffers: [[0.1]],
            settings: [MixerSettings(volume: 1, pan: -1, delaySend: 1)],
            master: MasterSettings(volume: 1, delayTimeBeats: 4, delayFeedback: 0.95),
            sampleRate: 48_000, tempo: 40, looping: true)
        // A long delay reduces to a one-frame cycle without a delay-sized queue.
        // With cross-feedback, dry+wet values are 0.1+0.1/(1-0.95^2) and
        // 0.1*0.95/(1-0.95^2) before the existing master limiter.
        XCTAssertEqual(output.frameCount, 1)
        XCTAssertTrue((output.left + output.right).allSatisfy { $0.isFinite && abs($0) <= 1 })
        XCTAssertGreaterThan(output.left[0], 0.95)
        XCTAssertGreaterThan(output.right[0], 0.95)
    }

    private func rms(_ samples: [Float]) -> Double {
        sqrt(samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count)))
    }
}
