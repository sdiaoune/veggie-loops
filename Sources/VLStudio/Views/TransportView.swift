import SwiftUI
import VLCore

struct TransportView: View {
    @Bindable var state: AppState
    @Binding var showsMixer: Bool

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "leaf.fill").font(.system(size: 26)).foregroundStyle(StudioAppearance.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("VL STUDIO").font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(1.3)
                    Text("Veggie Loops").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 155, alignment: .leading)
            HStack(spacing: 6) {
                Button(action: state.togglePlayback) {
                    Image(systemName: state.isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold)).frame(width: 32, height: 27)
                }
                .buttonStyle(.borderedProminent)
                .help("Play / stop (Space)")
                .accessibilityLabel(state.isPlaying ? "Stop playback" : "Play playback")
                .accessibilityIdentifier("playButton")
                Button(action: state.stopPlayback) {
                    Image(systemName: "stop.fill").font(.system(size: 13)).frame(width: 27, height: 27)
                }
                .help("Stop and return to the beginning")
                .accessibilityLabel("Stop playback")
                .accessibilityIdentifier("stopButton")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("TEMPO").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1)
                HStack(spacing: 3) {
                    TextField("BPM", value: tempoBinding, format: .number.precision(.fractionLength(0...1)))
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                        .textFieldStyle(.plain).frame(width: 56)
                        .accessibilityLabel("Tempo in beats per minute")
                        .accessibilityIdentifier("tempoField")
                    Stepper("Tempo", value: tempoBinding, in: 40...240, step: 1).labelsHidden().frame(width: 17)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("TRANSPORT").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1)
                Text(position).font(.system(size: 17, weight: .medium, design: .monospaced))
                    .monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(width: 104, alignment: .leading)
                    .accessibilityLabel("Bar and beat \(position)")
                    .accessibilityIdentifier("transportPosition")
            }
            Picker("Playback mode", selection: Binding(get: { state.mode }, set: state.changeMode)) {
                Text("Pattern").tag(PlaybackMode.pattern)
                Text("Song").tag(PlaybackMode.song)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 130)
            .accessibilityIdentifier("playbackModePicker")
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.isDirty ? "PROJECT · UNSAVED" : "PROJECT")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(1)
                TextField("Project name", text: Binding(get: { state.project.name }, set: { name in state.edit { $0.name = String(name.prefix(200)) } }))
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .medium))
                    .accessibilityIdentifier("projectNameField")
            }
            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button(action: state.saveProject) { Image(systemName: "square.and.arrow.down") }
                    .help("Save project (⌘S)").accessibilityLabel("Save project")
                    .accessibilityIdentifier("saveButton")
                Button(action: state.exportWAV) {
                    HStack(spacing: 5) {
                        if state.isExporting { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "waveform") }
                        Text(state.isExporting ? "Rendering" : "Export WAV")
                    }
                }
                .disabled(state.isExporting).accessibilityIdentifier("exportButton")
                Button { showsMixer.toggle() } label: { Image(systemName: "slider.vertical.3") }
                    .help(showsMixer ? "Hide mixer" : "Show mixer")
                    .accessibilityLabel(showsMixer ? "Hide mixer" : "Show mixer")
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 16).frame(height: 74)
        .background(.bar)
    }

    private var tempoBinding: Binding<Double> {
        Binding(get: { state.project.tempo }, set: { value in
            guard value.isFinite else { return }
            state.edit { $0.tempo = min(240, max(40, value)) }
        })
    }

    private var position: String {
        let beat = max(0, state.playheadBeat)
        return String(format: "%02d:%02d:%02d", Int(beat) / 4 + 1, Int(beat) % 4 + 1, Int((beat.truncatingRemainder(dividingBy: 1)) * 100))
    }
}
