import SwiftUI
import VLCore

struct StudioView: View {
    @Bindable var state: AppState
    @State private var showsMixer = true

    var body: some View {
        VStack(spacing: 0) {
            TransportView(state: state, showsMixer: $showsMixer)
            Divider()
            HStack(spacing: 0) {
                TrackSidebarView(state: state).frame(width: 184)
                Divider()
                VStack(spacing: 0) {
                    editorHeader
                    Divider()
                    Group {
                        switch state.editor {
                        case .sequencer: SequencerView(state: state)
                        case .pianoRoll: PianoRollView(state: state)
                        case .arrangement: ArrangementView(state: state)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsMixer {
                Divider()
                MixerView(state: state).frame(height: 246)
            }
            Divider()
            statusBar
        }
        .tint(StudioAppearance.accent)
        .frame(minWidth: 1050, minHeight: 720)
    }

    private var editorHeader: some View {
        HStack(spacing: 18) {
            Picker("Editor", selection: $state.editor) {
                Label("Channel rack", systemImage: "square.grid.3x3").tag(EditorPage.sequencer)
                Label("Piano roll", systemImage: "pianokeys").tag(EditorPage.pianoRoll)
                Label("Arrangement", systemImage: "rectangle.split.3x1").tag(EditorPage.arrangement)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 410)
            .accessibilityIdentifier("editorPicker")
            Spacer(minLength: 0)
            if state.editor == .arrangement {
                Picker("Song bars", selection: Binding(get: { state.project.arrangementBars }, set: { bars in
                    state.edit { project in
                        project.arrangementBars = bars
                        project.clips.removeAll { $0.startBar >= bars }
                        for index in project.clips.indices {
                            project.clips[index].lengthBars = min(project.clips[index].lengthBars, bars - project.clips[index].startBar)
                        }
                    }
                })) {
                    ForEach([4, 8, 16], id: \.self) { Text("\($0) bars").tag($0) }
                }
                .frame(width: 135)
            } else {
                Picker("Pattern", selection: Binding(get: { state.project.patternBars }, set: changePatternBars)) {
                    ForEach(1...4, id: \.self) { Text("\($0) \($0 == 1 ? "bar" : "bars")").tag($0) }
                }
                .frame(width: 128)
                .accessibilityIdentifier("patternBarsPicker")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func changePatternBars(_ bars: Int) {
        state.edit { project in
            project.patternBars = bars
            let beats = Double(bars * 4)
            for trackIndex in project.tracks.indices {
                project.tracks[trackIndex].notes.removeAll { $0.beat >= beats }
                for noteIndex in project.tracks[trackIndex].notes.indices {
                    let remaining = beats - project.tracks[trackIndex].notes[noteIndex].beat
                    project.tracks[trackIndex].notes[noteIndex].duration = min(project.tracks[trackIndex].notes[noteIndex].duration, remaining)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle().fill(state.isPlaying ? StudioAppearance.accent : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
            Text(state.statusMessage).lineLimit(1).accessibilityIdentifier("statusMessage")
            Spacer()
            Text("\(state.project.tracks.count) channels")
            Text("48 kHz · Stereo").foregroundStyle(.tertiary)
            Text("VEGGIE LOOPS").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.5)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 16).frame(height: 28)
    }
}
