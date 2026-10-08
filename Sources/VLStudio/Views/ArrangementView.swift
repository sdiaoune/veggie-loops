import SwiftUI
import VLCore

struct ArrangementView: View {
    @Bindable var state: AppState
    private let rowHeight: CGFloat = 60
    private let channelWidth: CGFloat = 136

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StudioPanelTitle(title: "Arrangement", subtitle: "Click a bar to add a pattern · click a clip to remove")
                Button("Fill selected row", action: fillSelectedTrack).disabled(state.selectedTrackID == nil)
                    .accessibilityIdentifier("fillArrangementButton")
                Button("Clear") { state.edit { $0.clips = [] } }.disabled(state.project.clips.isEmpty)
                    .accessibilityLabel("Clear arrangement")
            }
            .controlSize(.small).padding(.horizontal, 18).frame(height: 44)
            if state.project.tracks.isEmpty {
                ContentUnavailableView("Arrange your channels", systemImage: "rectangle.split.3x1", description: Text("Add instrument channels, write their patterns, then place clips here."))
            } else {
                GeometryReader { geometry in
                    let barWidth = max(68, (geometry.size.width - channelWidth - 28) / CGFloat(state.project.arrangementBars))
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                Text("CHANNEL").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                                    .frame(width: channelWidth, height: 28, alignment: .leading)
                                ForEach(0..<state.project.arrangementBars, id: \.self) { bar in
                                    Text("\(bar + 1)").font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary).frame(width: barWidth, height: 28, alignment: .leading)
                                }
                            }
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    ForEach(state.project.tracks) { track in arrangementRow(track, barWidth: barWidth) }
                                }
                                if state.isPlaying && state.mode == .song {
                                    Rectangle().fill(StudioAppearance.accent)
                                        .frame(width: 1.5, height: CGFloat(state.project.tracks.count) * rowHeight)
                                        .offset(x: channelWidth + CGFloat(state.playheadBeat / 4) * barWidth)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.bottom, 16)
                    }
                }
            }
        }
    }

    private func arrangementRow(_ track: Track, barWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button { state.selectedTrackID = track.id } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(StudioAppearance.color(track.colorIndex)).frame(width: 3, height: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(track.instrument.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, 10).frame(width: channelWidth, height: rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<state.project.arrangementBars, id: \.self) { bar in
                        Button { state.selectedTrackID = track.id; state.toggleClip(trackID: track.id, bar: bar) } label: {
                            Rectangle().fill(Color.primary.opacity(bar % 2 == 0 ? 0.035 : 0.055))
                                .overlay(alignment: .leading) { Rectangle().fill(.primary.opacity(bar % 4 == 0 ? 0.2 : 0.1)).frame(width: 0.5) }
                                .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 0.5) }
                                .frame(width: barWidth, height: rowHeight)
                        }
                        .buttonStyle(.plain).help("Place \(track.name) pattern at bar \(bar + 1)")
                        .accessibilityLabel("\(track.name) arrangement bar \(bar + 1)")
                        .accessibilityIdentifier("clipCell-\(track.id.uuidString)-\(bar)")
                    }
                }
                ForEach(state.project.clips.filter { $0.trackID == track.id }) { clip in
                    clipButton(clip, track: track, barWidth: barWidth)
                }
            }
            .frame(width: barWidth * CGFloat(state.project.arrangementBars), height: rowHeight)
        }
        .background(state.selectedTrackID == track.id ? StudioAppearance.color(track.colorIndex).opacity(0.045) : Color.clear)
        .opacity(track.mixer.muted ? 0.5 : 1)
    }

    private func clipButton(_ clip: ArrangementClip, track: Track, barWidth: CGFloat) -> some View {
        let color = StudioAppearance.color(track.colorIndex)
        return Button { state.selectedTrackID = track.id; state.toggleClip(trackID: track.id, bar: clip.startBar) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).padding(.horizontal, 6)
                Canvas { context, size in
                    let total = Double(clip.lengthBars * 4)
                    let repeats = Int(ceil(total / state.project.patternBeats))
                    for repeatIndex in 0..<repeats {
                        for note in track.notes {
                            let beat = note.beat + Double(repeatIndex) * state.project.patternBeats
                            guard beat < total else { continue }
                            let x = beat / total * size.width
                            let width = max(2, min(note.duration, total - beat) / total * size.width)
                            let y = track.instrument.isDrum ? size.height * 0.55 : size.height * (1 - Double(note.midiNote % 24) / 24)
                            context.fill(Path(CGRect(x: x, y: y, width: width, height: 2)), with: .color(Color.primary.opacity(0.65)))
                        }
                    }
                }
                .padding(.horizontal, 6).frame(height: 22)
            }
            .frame(width: max(10, CGFloat(clip.lengthBars) * barWidth - 4), height: rowHeight - 8)
            .background(color.opacity(0.28), in: RoundedRectangle(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.6), lineWidth: 1) }
        }
        .buttonStyle(.plain).offset(x: CGFloat(clip.startBar) * barWidth + 2, y: 4)
        .help("\(track.name) · bars \(clip.startBar + 1)–\(clip.startBar + clip.lengthBars) · click to remove")
        .accessibilityLabel("Remove \(track.name) clip at bar \(clip.startBar + 1)")
        .accessibilityIdentifier("clip-\(clip.id.uuidString)")
    }

    private func fillSelectedTrack() {
        guard let id = state.selectedTrackID else { return }
        state.edit { project in
            project.clips.removeAll { $0.trackID == id }
            for bar in stride(from: 0, to: project.arrangementBars, by: project.patternBars) {
                project.clips.append(ArrangementClip(trackID: id, startBar: bar, lengthBars: min(project.patternBars, project.arrangementBars - bar)))
            }
        }
    }
}
