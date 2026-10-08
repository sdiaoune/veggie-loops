import AVFoundation
import Foundation
import VLCore
import VLAudio

@main
struct VLSmoke {
    @MainActor static func main() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let output = URL(fileURLWithPath: args.first(where: { !$0.hasPrefix("--") }) ?? "dist/verification", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let project = VLProject.demo()
        let pattern = try AudioRenderer.render(project: project, mode: .pattern)
        let song = try AudioRenderer.render(project: project, mode: .song)
        guard pattern.frameCount > 0, song.frameCount > pattern.frameCount,
              pattern.left.allSatisfy(\.isFinite), pattern.right.allSatisfy(\.isFinite),
              pattern.left.contains(where: { abs($0) > 0.01 }) else {
            throw ProjectError.invalid("The demo did not render finite, audible PCM.")
        }
        let wavURL = output.appendingPathComponent("Fresh-produce.wav")
        try AudioRenderer.writeWAV(song, to: wavURL)
        let decoded = try AVAudioFile(forReading: wavURL)
        guard decoded.length == song.frameCount, decoded.processingFormat.channelCount == 2 else {
            throw ProjectError.invalid("The WAV did not decode as the expected stereo audio.")
        }
        let projectURL = output.appendingPathComponent("Fresh-produce.vlp")
        try ProjectDocument.save(project, to: projectURL)
        guard try ProjectDocument.load(from: projectURL) == project else {
            throw ProjectError.invalid("Project persistence changed musical data.")
        }
        var report: [String: Any] = [
            "project_roundtrip": true, "wav_decode": true, "sample_rate": song.sampleRate,
            "pattern_frames": pattern.frameCount, "song_frames": song.frameCount,
            "song_seconds": song.duration,
            "peak": song.left.reduce(Float.zero) { max($0, abs($1)) },
            "tracks": project.tracks.map(\.name)
        ]
        if args.contains("--playback") {
            let engine = VLAudioEngine()
            try await engine.play(project: project, mode: .pattern)
            try await Task.sleep(nanoseconds: 900_000_000)
            let beat = engine.currentBeat
            let levels = engine.levels
            guard engine.isPlaying, beat > 0.1, max(levels.left, levels.right) > 0 else {
                engine.stop()
                throw ProjectError.invalid("Native audio playback did not advance or meter audio.")
            }
            var changed = project
            changed.tracks[0].mixer.muted = true
            try await engine.refresh(project: changed, mode: .pattern)
            try await Task.sleep(nanoseconds: 250_000_000)
            guard engine.isPlaying else { throw ProjectError.invalid("Live mixer refresh stopped playback.") }
            engine.stop()
            guard !engine.isPlaying else { throw ProjectError.invalid("Stop did not stop playback.") }
            report["native_playback"] = true
            report["transport_beat"] = beat
            report["master_meter"] = max(levels.left, levels.right)
            report["live_refresh"] = true
            report["stop"] = true
        }
        let reportURL = output.appendingPathComponent("verification.json")
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: reportURL, options: .atomic)
        print(String(decoding: data, as: UTF8.self))
        print("WAV: \(wavURL.path)")
        print("Project: \(projectURL.path)")
    }
}
