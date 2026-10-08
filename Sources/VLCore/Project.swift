import Foundation

public enum InstrumentKind: String, Codable, CaseIterable, Sendable {
    case kick, snare, hat, bass, synth, sample
    public var title: String { rawValue.capitalized }
    public var isDrum: Bool { self == .kick || self == .snare || self == .hat }
    public var defaultPitch: Int { self == .bass ? 36 : 60 }
}

public enum PlaybackMode: String, Codable, CaseIterable, Sendable {
    case pattern, song
}

public struct NoteEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var beat: Double
    public var duration: Double
    public var midiNote: Int
    public var velocity: Double
    public init(id: UUID = UUID(), beat: Double, duration: Double = 0.25, midiNote: Int = 60, velocity: Double = 0.8) {
        self.id = id; self.beat = beat; self.duration = duration
        self.midiNote = midiNote; self.velocity = velocity
    }
}

public struct MixerSettings: Codable, Equatable, Sendable {
    public var volume: Double
    public var pan: Double
    public var muted: Bool
    public var solo: Bool
    public var cutoffHz: Double
    public var delaySend: Double
    public var drive: Double
    public init(volume: Double = 0.8, pan: Double = 0, muted: Bool = false, solo: Bool = false,
                cutoffHz: Double = 20_000, delaySend: Double = 0, drive: Double = 0) {
        self.volume = volume; self.pan = pan; self.muted = muted; self.solo = solo
        self.cutoffHz = cutoffHz; self.delaySend = delaySend; self.drive = drive
    }
}

public struct MasterSettings: Codable, Equatable, Sendable {
    public var volume: Double
    public var delayTimeBeats: Double
    public var delayFeedback: Double
    public init(volume: Double = 0.8, delayTimeBeats: Double = 0.75, delayFeedback: Double = 0.35) {
        self.volume = volume; self.delayTimeBeats = delayTimeBeats; self.delayFeedback = delayFeedback
    }
}

public struct Track: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var instrument: InstrumentKind
    public var notes: [NoteEvent]
    public var samplePath: String?
    public var mixer: MixerSettings
    public var colorIndex: Int
    public init(id: UUID = UUID(), name: String, instrument: InstrumentKind, notes: [NoteEvent] = [],
                samplePath: String? = nil, mixer: MixerSettings = MixerSettings(), colorIndex: Int = 0) {
        self.id = id; self.name = name; self.instrument = instrument; self.notes = notes
        self.samplePath = samplePath; self.mixer = mixer; self.colorIndex = colorIndex
    }
}

public struct ArrangementClip: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var trackID: UUID
    public var startBar: Int
    public var lengthBars: Int
    public init(id: UUID = UUID(), trackID: UUID, startBar: Int, lengthBars: Int = 1) {
        self.id = id; self.trackID = trackID; self.startBar = startBar; self.lengthBars = lengthBars
    }
}

public struct VLProject: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var id: UUID
    public var name: String
    public var tempo: Double
    public var patternBars: Int
    public var arrangementBars: Int
    public var tracks: [Track]
    public var clips: [ArrangementClip]
    public var master: MasterSettings
    public var patternBeats: Double { Double(patternBars * 4) }
    public func lengthBeats(for mode: PlaybackMode) -> Double {
        mode == .pattern ? patternBeats : Double(arrangementBars * 4)
    }
    public init(formatVersion: Int = 1, id: UUID = UUID(), name: String = "Untitled garden", tempo: Double = 120,
                patternBars: Int = 1, arrangementBars: Int = 8, tracks: [Track] = [],
                clips: [ArrangementClip] = [], master: MasterSettings = MasterSettings()) {
        self.formatVersion = formatVersion; self.id = id; self.name = name; self.tempo = tempo
        self.patternBars = patternBars; self.arrangementBars = arrangementBars
        self.tracks = tracks; self.clips = clips; self.master = master
    }
}

public struct StereoBuffer: Sendable {
    public var left: [Float]
    public var right: [Float]
    public var sampleRate: Double
    public var frameCount: Int { min(left.count, right.count) }
    public var duration: Double { Double(frameCount) / sampleRate }
    public init(left: [Float], right: [Float], sampleRate: Double) {
        self.left = left; self.right = right; self.sampleRate = sampleRate
    }
}

public struct AudioLevels: Equatable, Sendable {
    public var left: Double
    public var right: Double
    public var tracks: [UUID: Double]
    public init(left: Double = 0, right: Double = 0, tracks: [UUID: Double] = [:]) {
        self.left = left; self.right = right; self.tracks = tracks
    }
}
