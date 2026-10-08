import Foundation

extension VLProject {
    public static func demo() -> VLProject {
        func drum(_ steps: [Int], velocity: Double = 0.85) -> [NoteEvent] {
            steps.map { NoteEvent(beat: Double($0) / 4, duration: 0.25, velocity: velocity) }
        }
        let kick = Track(name: "Carrot kick", instrument: .kick,
                         notes: drum([0, 6, 8, 14, 16, 22, 24, 28]), mixer: MixerSettings(volume: 0.92), colorIndex: 0)
        let snare = Track(name: "Radish snare", instrument: .snare,
                          notes: drum([4, 12, 20, 28], velocity: 0.8), mixer: MixerSettings(volume: 0.6, pan: -0.08), colorIndex: 1)
        let hat = Track(name: "Sprout hats", instrument: .hat,
                        notes: (0..<16).map { NoteEvent(beat: Double($0) * 0.5, duration: 0.125, velocity: $0 % 2 == 0 ? 0.6 : 0.38) },
                        mixer: MixerSettings(volume: 0.5, pan: 0.22), colorIndex: 2)
        let bass = Track(name: "Beet bass", instrument: .bass,
                         notes: [(0.0, 36), (1.5, 36), (2.0, 43), (3.0, 39), (4.0, 36), (5.5, 39), (6.0, 43), (7.0, 34)]
                            .map { NoteEvent(beat: $0.0, duration: 0.5, midiNote: $0.1, velocity: 0.7) },
                         mixer: MixerSettings(volume: 0.67, cutoffHz: 2200, drive: 0.12), colorIndex: 3)
        let synth = Track(name: "Pea keys", instrument: .synth,
                          notes: [(0.0, 60), (0.0, 63), (0.0, 67), (2.0, 58), (2.0, 62), (2.0, 65),
                                  (4.0, 56), (4.0, 60), (4.0, 63), (6.0, 58), (6.0, 62), (6.0, 65)]
                            .map { NoteEvent(beat: $0.0, duration: 1.5, midiNote: $0.1, velocity: 0.48) },
                          mixer: MixerSettings(volume: 0.38, pan: -0.16, cutoffHz: 6500, delaySend: 0.28), colorIndex: 4)
        let tracks = [kick, snare, hat, bass, synth]
        let clips = tracks.enumerated().flatMap { index, track in
            stride(from: index == 4 ? 2 : 0, to: 8, by: 2).map {
                ArrangementClip(trackID: track.id, startBar: $0, lengthBars: 2)
            }
        }
        return VLProject(name: "Fresh produce", tempo: 112, patternBars: 2, arrangementBars: 8,
                         tracks: tracks, clips: clips, master: MasterSettings(volume: 0.8))
    }

    public static func empty() -> VLProject {
        let tracks = [InstrumentKind.kick, .snare, .hat, .bass, .synth].enumerated().map {
            Track(name: $0.element.title, instrument: $0.element, colorIndex: $0.offset)
        }
        return VLProject(tracks: tracks)
    }
}
