import SwiftUI
import VLCore

struct SequencerView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StudioPanelTitle(title: "Channel rack", subtitle: "Click a step to plant a note · 1/16 grid")
                Button("Piano roll") { state.editor = .pianoRoll }.disabled(state.selectedTrack == nil)
                Button("Clear channel") {
                    guard let id = state.selectedTrackID else { return }
                    state.edit { project in
                        if let index = project.tracks.firstIndex(where: { $0.id == id }) { project.tracks[index].notes = [] }
                    }
                }
                .disabled(state.selectedTrack?.notes.isEmpty != false)
                .accessibilityIdentifier("clearChannelButton")
            }
            .controlSize(.small).padding(.horizontal, 18).frame(height: 44)
            if state.project.tracks.isEmpty {
                ContentUnavailableView("Grow your first loop", systemImage: "leaf", description: Text("Add a kick, snare, bass or synth channel using the + menu."))
            } else {
                GeometryReader { geometry in
                    let steps = state.project.patternBars * 16
                    let cellWidth = max(25, min(42, (geometry.size.width - 180) / CGFloat(steps)))
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 4) {
                            stepHeader(steps: steps, cellWidth: cellWidth)
                            ForEach(state.project.tracks) { track in
                                channelRow(track, steps: steps, cellWidth: cellWidth)
                            }
                            Spacer(minLength: 20)
                        }
                        .padding(.horizontal, 14).padding(.bottom, 14)
                        .frame(minWidth: geometry.size.width, alignment: .leading)
                    }
                }
            }
        }
    }

    private func stepHeader(steps: Int, cellWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text("INSTRUMENT").font(.system(size: 9, weight: .semibold)).tracking(1)
                .frame(width: 146, alignment: .leading)
            ForEach(0..<steps, id: \.self) { step in
                Text(step % 4 == 0 ? "\(step / 16 + 1).\((step / 4) % 4 + 1)" : "·")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .frame(width: cellWidth - 4, height: 22)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func channelRow(_ track: Track, steps: Int, cellWidth: CGFloat) -> some View {
        let color = StudioAppearance.color(track.colorIndex)
        return HStack(spacing: 4) {
            HStack(spacing: 8) {
                Button { state.audition(track.id) } label: {
                    Image(systemName: StudioAppearance.instrumentIcon(track.instrument))
                        .font(.system(size: 13)).foregroundStyle(color).frame(width: 21, height: 28)
                }
                .buttonStyle(.plain).help("Preview \(track.name)")
                .accessibilityLabel("Preview \(track.name)")
                Button { state.selectedTrackID = track.id } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\(track.notes.count) notes").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Open piano roll") { state.selectedTrackID = track.id; state.editor = .pianoRoll } }
                LevelMeter(value: state.levels.tracks[track.id] ?? 0).frame(width: 4, height: 26)
            }
            .frame(width: 146)
            ForEach(0..<steps, id: \.self) { step in
                let note = track.notes.first { abs($0.beat - Double(step) / 4) < 0.001 }
                let currentStep = Int(state.playheadBeat.truncatingRemainder(dividingBy: state.project.patternBeats) * 4)
                Button { state.toggleStep(trackID: track.id, step: step) } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(note != nil ? color.opacity(0.55 + (note?.velocity ?? 0) * 0.4) : Color.primary.opacity((step / 4) % 2 == 0 ? 0.075 : 0.13))
                        .overlay {
                            if note != nil {
                                RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.6)).frame(width: 3, height: 10)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(state.isPlaying && step == currentStep ? color : Color.primary.opacity(0.05), lineWidth: state.isPlaying && step == currentStep ? 2 : 1)
                        }
                        .frame(width: cellWidth - 4, height: 29)
                }
                .buttonStyle(.plain)
                .help("\(track.name) · bar \(step / 16 + 1), step \(step % 16 + 1)")
                .accessibilityLabel("\(track.name) step \(step + 1)")
                .accessibilityValue(note == nil ? "Off" : "On")
                .accessibilityIdentifier("step-\(track.id.uuidString)-\(step)")
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 8)
        .background(state.selectedTrackID == track.id ? color.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .opacity(track.mixer.muted ? 0.5 : 1)
    }
}
