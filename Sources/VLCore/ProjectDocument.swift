import Foundation

public enum ProjectError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

extension VLProject {
    /// Bounded documents keep malformed data away from the renderer.
    @discardableResult public func validated() throws -> VLProject {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw ProjectError.invalid(message) }
        }
        func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Bool {
            value.isFinite && range.contains(value)
        }
        try require(formatVersion == 1, "This project uses an unsupported file version.")
        try require(name.count <= 200, "Project names must be under 200 characters.")
        try require(bounded(tempo, 40...240), "Tempo must be between 40 and 240 BPM.")
        try require((1...4).contains(patternBars), "Patterns must have one to four bars.")
        try require((1...16).contains(arrangementBars), "Songs must have one to sixteen bars.")
        try require(tracks.count <= 16, "A project can contain up to 16 tracks.")
        try require(Set(tracks.map(\.id)).count == tracks.count, "Track IDs must be unique.")
        try require(tracks.reduce(0) { $0 + $1.notes.count } <= 4096, "The project has too many notes.")
        try require(clips.count <= 256, "The project has too many clips.")
        try require(Set(clips.map(\.id)).count == clips.count, "Clip IDs must be unique.")
        let trackIDs = Set(tracks.map(\.id))
        for track in tracks {
            try require(track.name.count <= 100, "Track names must be under 100 characters.")
            try require((0...15).contains(track.colorIndex), "Invalid track color.")
            try require(Set(track.notes.map(\.id)).count == track.notes.count, "Note IDs must be unique within a track.")
            if let path = track.samplePath {
                try require(path.count <= 4096 && path.hasPrefix("/"), "Sample references must use an absolute path.")
            }
            let mix = track.mixer
            try require(bounded(mix.volume, 0...2) && bounded(mix.pan, -1...1), "Invalid track gain or pan.")
            try require(bounded(mix.cutoffHz, 20...20000) && bounded(mix.delaySend, 0...1) && bounded(mix.drive, 0...1), "Invalid track effect settings.")
            for note in track.notes {
                try require(bounded(note.beat, 0...patternBeats) && note.beat < patternBeats,
                            "A note falls outside its pattern.")
                try require(bounded(note.duration, 0.0625...patternBeats) && note.beat + note.duration <= patternBeats + 0.000001,
                            "A note length falls outside its pattern.")
                try require((0...127).contains(note.midiNote) && bounded(note.velocity, 0...1), "Invalid note pitch or velocity.")
            }
        }
        for clip in clips {
            try require(trackIDs.contains(clip.trackID), "A clip references a missing track.")
            try require(clip.startBar >= 0 && clip.startBar < arrangementBars && clip.lengthBars > 0 &&
                        clip.lengthBars <= arrangementBars - clip.startBar, "A clip falls outside the song.")
        }
        try require(bounded(master.volume, 0...2) && bounded(master.delayTimeBeats, 0.125...4) &&
                    bounded(master.delayFeedback, 0...0.85), "Invalid master settings.")
        return self
    }
}

public enum ProjectDocument {
    public static func encode(_ project: VLProject) throws -> Data {
        try project.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    public static func decode(_ data: Data) throws -> VLProject {
        guard data.count <= 4_000_000 else { throw ProjectError.invalid("This project exceeds the 4 MB document limit.") }
        let project = try JSONDecoder().decode(VLProject.self, from: data)
        return try project.validated()
    }

    public static func load(from url: URL) throws -> VLProject {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4_000_000 else { throw ProjectError.invalid("This project exceeds the 4 MB document limit.") }
        return try decode(Data(contentsOf: url))
    }

    public static func save(_ project: VLProject, to url: URL) throws {
        try encode(project).write(to: url, options: .atomic)
    }
}
