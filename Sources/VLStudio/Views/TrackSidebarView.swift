import SwiftUI
import VLCore

struct TrackSidebarView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CHANNELS").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(InstrumentKind.allCases, id: \.self) { instrument in
                        Button { state.addTrack(instrument) } label: {
                            Label(instrument.title, systemImage: StudioAppearance.instrumentIcon(instrument))
                        }
                    }
                } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)) }
                .menuStyle(.borderlessButton).frame(width: 20)
                .help("Add an instrument channel").accessibilityLabel("Add channel")
                .accessibilityIdentifier("addChannelMenu")
            }
            .padding(.horizontal, 14).frame(height: 43)
            List(selection: $state.selectedTrackID) {
                ForEach(state.project.tracks) { track in
                    HStack(spacing: 10) {
                        Image(systemName: StudioAppearance.instrumentIcon(track.instrument))
                            .font(.system(size: 15)).foregroundStyle(StudioAppearance.color(track.colorIndex))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text(track.instrument.title + (track.mixer.muted ? " · muted" : track.mixer.solo ? " · solo" : ""))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4).tag(track.id)
                    .accessibilityLabel("\(track.name), \(track.instrument.title)")
                    .contextMenu {
                        Button("Preview sound") { state.audition(track.id) }
                        Button("Open piano roll") { state.selectedTrackID = track.id; state.editor = .pianoRoll }
                        Button("Import sample…") { state.importSample(trackID: track.id) }
                        Divider()
                        Button("Delete channel", role: .destructive) { state.deleteTrack(track.id) }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("channelList")
            Divider()
            if let track = state.selectedTrack {
                selectedChannel(track)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "leaf").foregroundStyle(StudioAppearance.accent)
                    Text("Add a channel to start").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(20)
            }
        }
        .background(.regularMaterial)
    }

    private func selectedChannel(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SELECTED CHANNEL").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            TextField("Channel name", text: Binding(get: {
                state.project.tracks.first(where: { $0.id == track.id })?.name ?? track.name
            }, set: { name in state.edit { project in
                if let index = project.tracks.firstIndex(where: { $0.id == track.id }) { project.tracks[index].name = String(name.prefix(100)) }
            } }))
            .textFieldStyle(.roundedBorder).font(.system(size: 12))
            .accessibilityIdentifier("channelNameField")
            HStack {
                Button { state.audition(track.id) } label: { Label("Preview", systemImage: "speaker.wave.2") }
                    .accessibilityIdentifier("previewChannelButton")
                Spacer(minLength: 0)
                Button(role: .destructive) { state.deleteTrack(track.id) } label: { Image(systemName: "trash") }
                    .help("Delete \(track.name)").accessibilityLabel("Delete selected channel")
            }
            Button { state.importSample(trackID: track.id) } label: { Label("Import sample…", systemImage: "waveform.badge.plus") }
                .accessibilityIdentifier("importSampleButton")
            if let samplePath = track.samplePath {
                Text(URL(fileURLWithPath: samplePath).lastPathComponent).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .controlSize(.small).padding(14)
    }
}
