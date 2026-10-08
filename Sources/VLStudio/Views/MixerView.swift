import SwiftUI
import VLCore

struct MixerView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("MIXER").font(.system(size: 10, weight: .bold)).tracking(1.1)
                Text("Select a channel to shape its sound").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(state.isPlaying ? "LIVE" : "READY").font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(state.isPlaying ? StudioAppearance.accent : Color.secondary)
            }
            .padding(.horizontal, 16).frame(height: 29)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(state.project.tracks) { track in
                            ChannelStripView(state: state, track: track)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
                }
                Divider()
                MasterStripView(state: state).frame(width: 114).padding(.top, 8)
                Divider()
                MixerEffectsView(state: state).frame(width: 244).padding(.horizontal, 14).padding(.top, 9)
            }
        }
        .background(.thinMaterial)
    }
}

private struct ChannelStripView: View {
    @Bindable var state: AppState
    var track: Track

    var body: some View {
        VStack(spacing: 6) {
            Button { state.selectedTrackID = track.id } label: {
                HStack(spacing: 5) {
                    Circle().fill(StudioAppearance.color(track.colorIndex)).frame(width: 5, height: 5)
                    Text(track.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                .frame(width: 78, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Select \(track.name)")
            HStack(spacing: 4) {
                stateButton("M", active: track.mixer.muted, activeColor: .red) { change { $0.muted.toggle() } }
                    .accessibilityLabel("Mute \(track.name)")
                    .accessibilityIdentifier("mute-\(track.id.uuidString)")
                stateButton("S", active: track.mixer.solo, activeColor: .orange) { change { $0.solo.toggle() } }
                    .accessibilityLabel("Solo \(track.name)")
                    .accessibilityIdentifier("solo-\(track.id.uuidString)")
            }
            HStack(spacing: 7) {
                VerticalGainFader(value: binding(\.volume), label: "\(track.name) volume", identifier: "volume-\(track.id.uuidString)")
                    .frame(width: 28, height: 88)
                LevelMeter(value: state.levels.tracks[track.id] ?? 0).frame(width: 7, height: 82)
            }
            .frame(height: 90)
            Text(StudioAppearance.db(track.mixer.volume)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Text("L").font(.system(size: 8)).foregroundStyle(.secondary)
                Slider(value: binding(\.pan), in: -1...1).controlSize(.mini)
                    .accessibilityLabel("\(track.name) pan")
                    .accessibilityIdentifier("pan-\(track.id.uuidString)")
                Text("R").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .frame(width: 74)
        }
        .padding(.horizontal, 5).padding(.vertical, 3).frame(width: 88)
        .background(state.selectedTrackID == track.id ? StudioAppearance.color(track.colorIndex).opacity(0.085) : Color.primary.opacity(0.022), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1).fill(StudioAppearance.color(track.colorIndex).opacity(state.selectedTrackID == track.id ? 0.85 : 0.4))
                .frame(height: 2).padding(.horizontal, 7)
        }
    }

    private func stateButton(_ title: String, active: Bool, activeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .bold)).frame(width: 29, height: 19)
                .background(active ? activeColor.opacity(0.22) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(active ? activeColor : Color.secondary)
        }
        .buttonStyle(.plain).accessibilityValue(active ? "On" : "Off")
    }

    private func binding(_ keyPath: WritableKeyPath<MixerSettings, Double>) -> Binding<Double> {
        Binding(get: { state.project.tracks.first(where: { $0.id == track.id })?.mixer[keyPath: keyPath] ?? track.mixer[keyPath: keyPath] }, set: { value in change { $0[keyPath: keyPath] = value } })
    }

    private func change(_ transform: (inout MixerSettings) -> Void) {
        state.edit { project in
            guard let index = project.tracks.firstIndex(where: { $0.id == track.id }) else { return }
            transform(&project.tracks[index].mixer)
        }
    }
}

private struct MasterStripView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 6) {
            Text("MASTER").font(.system(size: 10, weight: .bold)).tracking(0.6).frame(height: 20)
            Text("STEREO OUT").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).frame(height: 19)
            HStack(spacing: 8) {
                VerticalGainFader(value: Binding(get: { state.project.master.volume }, set: { value in state.edit { $0.master.volume = value } }), label: "Master volume", identifier: "masterVolumeSlider")
                    .frame(width: 28, height: 88)
                HStack(spacing: 3) {
                    LevelMeter(value: state.levels.left).frame(width: 7, height: 82)
                    LevelMeter(value: state.levels.right).frame(width: 7, height: 82)
                }
            }
            .frame(height: 90)
            Text(StudioAppearance.db(state.project.master.volume)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            HStack(spacing: 10) { Text("L"); Text("R") }.font(.system(size: 8)).foregroundStyle(.secondary).frame(height: 20)
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
    }
}

private struct MixerEffectsView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let track = state.selectedTrack {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(StudioAppearance.color(track.colorIndex))
                    Text(track.name).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("CHANNEL FX").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                }
                .font(.system(size: 11, weight: .semibold)).frame(height: 16)
                effectSlider("Low-pass", value: cutoffBinding(track), range: log10(20)...log10(20_000), display: cutoffLabel(track.mixer.cutoffHz), id: "cutoffSlider")
                effectSlider("Drive", value: mixerBinding(track, \.drive), range: 0...1, display: "\(Int(track.mixer.drive * 100))%", id: "driveSlider")
                effectSlider("Delay send", value: mixerBinding(track, \.delaySend), range: 0...1, display: "\(Int(track.mixer.delaySend * 100))%", id: "delaySendSlider")
            } else {
                Text("Select a channel for effects").font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 110)
            }
            Divider()
            HStack(spacing: 8) {
                Text("Delay time").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Picker("Delay time", selection: Binding(get: { state.project.master.delayTimeBeats }, set: { value in state.edit { $0.master.delayTimeBeats = value } })) {
                    ForEach([0.125, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0], id: \.self) { beats in Text(String(format: "%g beats", beats)).tag(beats) }
                }
                .labelsHidden().frame(width: 95).controlSize(.mini)
                .accessibilityIdentifier("delayTimePicker")
            }
            effectSlider("Feedback", value: Binding(get: { state.project.master.delayFeedback }, set: { value in state.edit { $0.master.delayFeedback = value } }), range: 0...0.85, display: "\(Int(state.project.master.delayFeedback * 100))%", id: "delayFeedbackSlider")
        }
        .controlSize(.mini)
    }

    private func effectSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String, id: String) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title).accessibilityIdentifier(id)
            Text(display).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).frame(width: 43, alignment: .trailing)
        }
        .frame(height: 22)
    }

    private func mixerBinding(_ track: Track, _ keyPath: WritableKeyPath<MixerSettings, Double>) -> Binding<Double> {
        Binding(get: { state.project.tracks.first(where: { $0.id == track.id })?.mixer[keyPath: keyPath] ?? track.mixer[keyPath: keyPath] }, set: { value in
            state.edit { project in
                if let index = project.tracks.firstIndex(where: { $0.id == track.id }) { project.tracks[index].mixer[keyPath: keyPath] = value }
            }
        })
    }

    private func cutoffBinding(_ track: Track) -> Binding<Double> {
        let raw = mixerBinding(track, \.cutoffHz)
        return Binding(get: { log10(max(20, raw.wrappedValue)) }, set: { raw.wrappedValue = min(20_000, max(20, pow(10, $0))) })
    }

    private func cutoffLabel(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1fk", value / 1000) : String(format: "%.0f Hz", value)
    }
}
