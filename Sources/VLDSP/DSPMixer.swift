import Foundation
import VLCore

/// A deterministic offline mixer. Every channel is mono until its pan stage;
/// the shared delay and master bus are stereo. Output length includes only the
/// frames supplied by the renderer. Repeating playback can explicitly request
/// periodic delay state; the default remains a finite single-pass mix.
public enum DSPMixer {
    public static func mix(
        monoBuffers: [[Float]],
        settings: [MixerSettings],
        master: MasterSettings,
        sampleRate: Double,
        tempo: Double,
        looping: Bool = false
    ) -> StereoBuffer {
        let rate = bounded(sampleRate, fallback: 48_000, lower: 1, upper: 384_000)
        let frames = monoBuffers.map(\.count).max() ?? 0
        guard frames > 0 else {
            return StereoBuffer(left: [], right: [], sampleRate: rate)
        }

        let channels = monoBuffers.indices.map { index in
            index < settings.count ? settings[index] : MixerSettings()
        }
        let hasSolo = channels.contains { $0.solo && !$0.muted }
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)

        let bpm = bounded(tempo, fallback: 120, lower: 10, upper: 522)
        let delayBeats = bounded(master.delayTimeBeats, fallback: 0.75, lower: 0.0625, upper: 4)
        let requestedDelay = max(1, Int((rate * 60 / bpm * delayBeats).rounded()))
        let hasDelay = (looping || requestedDelay < frames) && channels.contains {
            !$0.muted && (!hasSolo || $0.solo) && $0.delaySend.isFinite && $0.delaySend > 0
        }
        var sendLeft = hasDelay ? [Float](repeating: 0, count: frames) : []
        var sendRight = hasDelay ? [Float](repeating: 0, count: frames) : []

        for index in monoBuffers.indices {
            let channel = channels[index]
            guard !channel.muted, !hasSolo || channel.solo else { continue }
            let volume = bounded(channel.volume, fallback: 0.8, lower: 0, upper: 2)
            guard volume > 0 else { continue }
            let pan = bounded(channel.pan, fallback: 0, lower: -1, upper: 1)
            let angle = (pan + 1) * .pi / 4
            // Explicit end points eliminate floating-point residue at hard pan.
            let gainLeft = pan == 1 ? 0 : cos(angle) * volume
            let gainRight = pan == -1 ? 0 : sin(angle) * volume
            let cutoff = bounded(channel.cutoffHz, fallback: 20_000, lower: 20, upper: 20_000)
            let filterEnabled = cutoff < min(20_000, rate * 0.45)
            let alpha = 1 - exp(-2 * .pi * cutoff / rate)
            let drive = bounded(channel.drive, fallback: 0, lower: 0, upper: 1)
            let driveGain = 1 + 18 * drive
            let driveNormalization = tanh(driveGain)
            let send = bounded(channel.delaySend, fallback: 0, lower: 0, upper: 1)
            var filterState = 0.0

            for frame in monoBuffers[index].indices {
                let raw = Double(monoBuffers[index][frame])
                // Invalid imported data becomes silence. This also bounds the
                // filter state when a caller supplies extreme finite samples.
                var signal = raw.isFinite ? min(32, max(-32, raw)) : 0
                if filterEnabled {
                    filterState += alpha * (signal - filterState)
                    signal = filterState
                }
                if drive > 0 {
                    let saturated = tanh(signal * driveGain) / driveNormalization
                    signal += drive * (saturated - signal)
                }
                let channelLeft = Float(signal * gainLeft)
                let channelRight = Float(signal * gainRight)
                left[frame] += channelLeft
                right[frame] += channelRight
                if hasDelay && send > 0 {
                    sendLeft[frame] += channelLeft * Float(send)
                    sendRight[frame] += channelRight * Float(send)
                }
            }
        }

        if hasDelay {
            let feedback = bounded(master.delayFeedback, fallback: 0.35, lower: 0, upper: 0.95)
            if looping {
                addLoopDelay(left: &left, right: &right, sendLeft: sendLeft, sendRight: sendRight,
                             delayFrames: requestedDelay, feedback: feedback)
            } else {
                addDelay(left: &left, right: &right, sendLeft: sendLeft, sendRight: sendRight,
                         delayFrames: requestedDelay, feedback: feedback)
            }
        }
        let masterGain = bounded(master.volume, fallback: 0.8, lower: 0, upper: 2)
        for frame in 0..<frames {
            left[frame] = limited(Double(left[frame]) * masterGain)
            right[frame] = limited(Double(right[frame]) * masterGain)
        }
        return StereoBuffer(left: left, right: right, sampleRate: rate)
    }

    private static func addDelay(
        left: inout [Float], right: inout [Float],
        sendLeft: [Float], sendRight: [Float],
        delayFrames: Int, feedback: Double
    ) {
        var lineLeft = [Float](repeating: 0, count: delayFrames)
        var lineRight = [Float](repeating: 0, count: delayFrames)
        let feedbackGain = Float(feedback)
        var cursor = 0
        for frame in left.indices {
            let echoLeft = lineLeft[cursor]
            let echoRight = lineRight[cursor]
            left[frame] += echoLeft
            right[frame] += echoRight
            // Cross-feedback makes successive echoes alternate sides while the
            // first repeat preserves the source's pan position.
            lineLeft[cursor] = sendLeft[frame] + echoRight * feedbackGain
            lineRight[cursor] = sendRight[frame] + echoLeft * feedbackGain
            cursor += 1
            if cursor == delayFrames { cursor = 0 }
        }
    }

    private static func addLoopDelay(
        left: inout [Float], right: inout [Float],
        sendLeft: [Float], sendRight: [Float],
        delayFrames: Int, feedback: Double
    ) {
        let frames = left.count
        let shift = delayFrames % frames
        let cycles = greatestCommonDivisor(frames, shift)
        let cycleLength = frames / cycles
        let cycleFeedback = pow(feedback, Double(cycleLength))
        let swapsChannels = !cycleLength.isMultiple(of: 2)

        // On a periodic input, echo[next] = send[current] + feedback *
        // swap(echo[current]), where next advances by the delay modulo frames.
        // Each index belongs to one of gcd(frames, shift) disjoint cycles.
        // A complete cycle gives e = b + f^L * swap^L(e). Solve that two-channel
        // system analytically, then visit every output frame once. Feedback is
        // bounded to 0.95 above, so both possible denominators stay positive.
        for start in 0..<cycles {
            var cursor = start
            var echoLeft = 0.0
            var echoRight = 0.0
            for _ in 0..<cycleLength {
                let nextLeft = Double(sendLeft[cursor]) + feedback * echoRight
                let nextRight = Double(sendRight[cursor]) + feedback * echoLeft
                echoLeft = nextLeft
                echoRight = nextRight
                cursor = advancedLoopIndex(cursor, shift: shift, frames: frames)
            }

            if swapsChannels {
                let denominator = 1 - cycleFeedback * cycleFeedback
                let initialLeft = (echoLeft + cycleFeedback * echoRight) / denominator
                let initialRight = (echoRight + cycleFeedback * echoLeft) / denominator
                echoLeft = initialLeft
                echoRight = initialRight
            } else {
                let denominator = 1 - cycleFeedback
                echoLeft /= denominator
                echoRight /= denominator
            }

            cursor = start
            for _ in 0..<cycleLength {
                left[cursor] += Float(echoLeft)
                right[cursor] += Float(echoRight)
                let nextLeft = Double(sendLeft[cursor]) + feedback * echoRight
                let nextRight = Double(sendRight[cursor]) + feedback * echoLeft
                echoLeft = nextLeft
                echoRight = nextRight
                cursor = advancedLoopIndex(cursor, shift: shift, frames: frames)
            }
        }
    }

    private static func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        var first = first
        var second = second
        while second != 0 {
            let remainder = first % second
            first = second
            second = remainder
        }
        return first
    }

    private static func advancedLoopIndex(_ index: Int, shift: Int, frames: Int) -> Int {
        // Avoid adding two potentially large indices before wrapping.
        let wrapPoint = frames - shift
        return index >= wrapPoint ? index - wrapPoint : index + shift
    }

    private static func bounded(_ value: Double, fallback: Double, lower: Double, upper: Double) -> Double {
        value.isFinite ? min(upper, max(lower, value)) : fallback
    }

    private static func limited(_ value: Double) -> Float {
        guard value.isFinite else { return 0 }
        let magnitude = abs(value)
        guard magnitude > 0.95 else { return Float(value) }
        // Leave quiet signals intact and round the peaks smoothly toward 0 dBFS.
        let compressed = 0.95 + 0.05 * tanh((magnitude - 0.95) / 0.05)
        return Float(value < 0 ? -compressed : compressed)
    }
}
