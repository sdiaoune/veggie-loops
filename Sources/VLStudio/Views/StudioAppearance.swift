import SwiftUI
import VLCore

enum StudioAppearance {
    static let accent = Color(red: 0.32, green: 0.72, blue: 0.43)
    static let trackColors: [Color] = [.green, .orange, .cyan, .purple, .pink, .yellow, .blue, .mint]
    static func color(_ index: Int) -> Color { trackColors[abs(index % trackColors.count)] }
    static func noteName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return "\(names[min(127, max(0, midi)) % 12])\(midi / 12 - 1)"
    }
    static func instrumentIcon(_ kind: InstrumentKind) -> String {
        switch kind {
        case .kick: return "circle.fill"
        case .snare: return "waveform.path"
        case .hat: return "sparkles"
        case .bass: return "guitars"
        case .synth: return "pianokeys"
        case .sample: return "waveform"
        }
    }
    static func db(_ value: Double) -> String {
        value > 0.000_01 ? String(format: "%.1f dB", 20 * log10(value)) : "−∞ dB"
    }
}

struct StudioPanelTitle: View {
    var title: String
    var subtitle: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

struct LevelMeter: View {
    var value: Double
    var vertical = true
    var body: some View {
        GeometryReader { geometry in
            let amount = min(1, max(0, value))
            ZStack(alignment: vertical ? .bottom : .leading) {
                RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 2)
                    .fill(amount > 0.92 ? Color.red : amount > 0.72 ? Color.orange : StudioAppearance.accent)
                    .frame(width: vertical ? geometry.size.width : geometry.size.width * amount,
                           height: vertical ? geometry.size.height * amount : geometry.size.height)
            }
        }
        .accessibilityLabel("Audio level")
        .accessibilityValue(StudioAppearance.db(value))
    }
}
