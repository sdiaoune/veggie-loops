import SwiftUI
import VLCore

struct PianoRollView: View {
    @Bindable var state: AppState
    @State private var baseOctave = 3
    @State private var selectedNoteID: UUID?
    private let keyWidth: CGFloat = 54
    private let rowHeight: CGFloat = 23

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                StudioPanelTitle(title: state.selectedTrack?.name ?? "Piano roll", subtitle: "Click empty grid to add · select a note to edit")
                Picker("Octave", selection: $baseOctave) {
                    ForEach(-1...8, id: \.self) { octave in Text("C\(octave) – \(min(octave + 1, 9))").tag(octave) }
                }
                .frame(width: 146).accessibilityIdentifier("pianoOctavePicker")
            }
            .controlSize(.small).padding(.horizontal, 18).frame(height: 44)
            if let track = state.selectedTrack {
                pianoGrid(track)
                Divider()
                if let note = track.notes.first(where: { $0.id == selectedNoteID }) {
                    NoteInspectorView(state: state, track: track, note: note) { selectedNoteID = nil }
                } else {
                    HStack {
                        Image(systemName: "cursorarrow.click").foregroundStyle(StudioAppearance.accent)
                        Text("Select a note to edit pitch, start, length and velocity.").foregroundStyle(.secondary)
                        Spacer()
                        Text("1/16 snap").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 11)).padding(.horizontal, 18).frame(height: 72)
                }
            } else {
                ContentUnavailableView("Select an instrument", systemImage: "pianokeys", description: Text("Choose a channel to write its melody."))
            }
        }
        .onAppear(perform: centerPitchRange)
        .onChange(of: state.selectedTrackID) { _, _ in selectedNoteID = nil; centerPitchRange() }
    }

    private var pitches: [Int] {
        Array((max(0, (baseOctave + 1) * 12)...min(127, (baseOctave + 3) * 12 - 1)).reversed())
    }

    private func centerPitchRange() {
        guard let track = state.selectedTrack else { return }
        let pitch = track.notes.first?.midiNote ?? track.instrument.defaultPitch
        baseOctave = max(-1, min(8, pitch / 12 - 2))
    }

    private func pianoGrid(_ track: Track) -> some View {
        GeometryReader { geometry in
            let steps = state.project.patternBars * 16
            let stepWidth = max(22, (geometry.size.width - keyWidth - 16) / CGFloat(steps))
            let width = CGFloat(steps) * stepWidth
            let height = CGFloat(pitches.count) * rowHeight
            // The timeline and note grid share horizontal movement. Only the pitch rows scroll vertically.
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("NOTE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: keyWidth, height: 24)
                        HStack(spacing: 0) {
                            ForEach(0..<steps, id: \.self) { step in
                                Text(step % 4 == 0 ? "\(step / 16 + 1).\((step / 4) % 4 + 1)" : "")
                                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                                    .frame(width: stepWidth, height: 24, alignment: .leading)
                            }
                        }
                    }
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            HStack(alignment: .top, spacing: 0) {
                                VStack(spacing: 0) {
                                    ForEach(pitches, id: \.self) { pitch in
                                        Button { state.audition(track.id, pitch: pitch) } label: {
                                            HStack {
                                                Text(StudioAppearance.noteName(pitch)).font(.system(size: 10, weight: pitch % 12 == 0 ? .bold : .regular, design: .monospaced))
                                                Spacer(minLength: 0)
                                            }
                                            .padding(.leading, 6).frame(width: keyWidth, height: rowHeight)
                                            .background(isBlackKey(pitch) ? Color.primary.opacity(0.14) : Color.primary.opacity(0.04))
                                            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5) }
                                        }
                                        .buttonStyle(.plain).help("Preview \(StudioAppearance.noteName(pitch))")
                                        .accessibilityLabel("Play \(StudioAppearance.noteName(pitch))")
                                        .id(pitch)
                                    }
                                }
                                ZStack(alignment: .topLeading) {
                                    Canvas { context, size in
                                        for (row, pitch) in pitches.enumerated() {
                                            let rect = CGRect(x: 0, y: CGFloat(row) * rowHeight, width: size.width, height: rowHeight)
                                            context.fill(Path(rect), with: .color(Color.primary.opacity(isBlackKey(pitch) ? 0.06 : 0.015)))
                                            var line = Path(); line.move(to: CGPoint(x: 0, y: rect.minY)); line.addLine(to: CGPoint(x: size.width, y: rect.minY))
                                            context.stroke(line, with: .color(Color.primary.opacity(pitch % 12 == 0 ? 0.17 : 0.06)), lineWidth: 0.5)
                                        }
                                        for step in 0...steps {
                                            var line = Path(); line.move(to: CGPoint(x: CGFloat(step) * stepWidth, y: 0)); line.addLine(to: CGPoint(x: CGFloat(step) * stepWidth, y: size.height))
                                            context.stroke(line, with: .color(Color.primary.opacity(step % 16 == 0 ? 0.23 : step % 4 == 0 ? 0.14 : 0.055)), lineWidth: step % 16 == 0 ? 1.5 : 0.5)
                                        }
                                    }
                                    .frame(width: width, height: height)
                                    .contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                                        let row = Int(gesture.location.y / rowHeight)
                                        let step = Int(gesture.location.x / stepWidth)
                                        guard pitches.indices.contains(row), (0..<steps).contains(step) else { return }
                                        let pitch = pitches[row]
                                        state.toggleNote(trackID: track.id, pitch: pitch, step: step)
                                        selectedNoteID = state.selectedTrack?.notes.first(where: { $0.midiNote == pitch && abs($0.beat - Double(step) / 4) < 0.001 })?.id
                                    })
                                    .accessibilityLabel("Piano roll note grid")
                                    .accessibilityIdentifier("pianoRollGrid")
                                    ForEach(track.notes) { note in
                                        if let row = pitches.firstIndex(of: note.midiNote) {
                                            noteButton(note, track: track, row: row, stepWidth: stepWidth)
                                        }
                                    }
                                    if state.isPlaying {
                                        Rectangle().fill(StudioAppearance.accent.opacity(0.8)).frame(width: 1.5, height: height)
                                            .offset(x: CGFloat(state.playheadBeat.truncatingRemainder(dividingBy: state.project.patternBeats)) * stepWidth * 4)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .frame(width: width, height: height)
                            }
                            .padding(.bottom, 8)
                        }
                        .frame(width: keyWidth + width, height: max(0, geometry.size.height - 24))
                        .onAppear { scrollToNotes(proxy, track: track) }
                        .onChange(of: track.id) { _, _ in scrollToNotes(proxy, track: track) }
                        .onChange(of: baseOctave) { _, _ in
                            let target = pitches.contains(track.instrument.defaultPitch) ? track.instrument.defaultPitch : pitches[pitches.count / 2]
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
                .padding(.trailing, 12)
            }
        }
    }

    private func scrollToNotes(_ proxy: ScrollViewProxy, track: Track) {
        let preferred = track.notes.first?.midiNote ?? track.instrument.defaultPitch
        let target = pitches.contains(preferred) ? preferred : pitches[pitches.count / 2]
        proxy.scrollTo(target, anchor: .center)
    }

    private func noteButton(_ note: NoteEvent, track: Track, row: Int, stepWidth: CGFloat) -> some View {
        Button { selectedNoteID = note.id; state.audition(track.id, pitch: note.midiNote) } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(StudioAppearance.color(track.colorIndex).opacity(selectedNoteID == note.id ? 0.95 : 0.72))
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white.opacity(0.4)).frame(width: 2).padding(.vertical, 3).padding(.leading, 3)
                }
                .overlay { RoundedRectangle(cornerRadius: 3).stroke(selectedNoteID == note.id ? Color.primary.opacity(0.7) : Color.clear, lineWidth: 1.5) }
                .frame(width: max(5, CGFloat(note.duration) * 4 * stepWidth - 2), height: rowHeight - 3)
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(note.beat) * 4 * stepWidth + 1, y: CGFloat(row) * rowHeight + 1.5)
        .help("\(StudioAppearance.noteName(note.midiNote)) · \(String(format: "%.2f", note.duration)) beats · velocity \(Int(note.velocity * 100))%")
        .accessibilityLabel("\(StudioAppearance.noteName(note.midiNote)) note at beat \(note.beat + 1)")
        .accessibilityIdentifier("note-\(note.id.uuidString)")
        .contextMenu {
            Button("Delete note", role: .destructive) { deleteNote(trackID: track.id, noteID: note.id) }
        }
    }

    private func deleteNote(trackID: UUID, noteID: UUID) {
        state.edit { project in
            if let index = project.tracks.firstIndex(where: { $0.id == trackID }) { project.tracks[index].notes.removeAll { $0.id == noteID } }
        }
        if selectedNoteID == noteID { selectedNoteID = nil }
    }

    private func isBlackKey(_ pitch: Int) -> Bool { [1, 3, 6, 8, 10].contains(pitch % 12) }
}

private struct NoteInspectorView: View {
    @Bindable var state: AppState
    var track: Track
    var note: NoteEvent
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                caption("PITCH")
                Stepper(value: pitchBinding, in: 0...127) { Text(StudioAppearance.noteName(note.midiNote)).font(.system(size: 12, weight: .semibold, design: .monospaced)).frame(width: 45, alignment: .leading) }
                    .accessibilityLabel("Selected note pitch").accessibilityIdentifier("notePitchStepper")
            }
            .frame(width: 86)
            VStack(alignment: .leading, spacing: 5) {
                caption("START · BEATS")
                Stepper(value: startBinding, in: 0...(state.project.patternBeats - 0.25), step: 0.25) {
                    Text(String(format: "%.2f", note.beat + 1)).font(.system(size: 12, design: .monospaced)).frame(width: 45, alignment: .leading)
                }
                .accessibilityLabel("Selected note start").accessibilityIdentifier("noteStartStepper")
            }
            .frame(width: 96)
            VStack(alignment: .leading, spacing: 3) {
                HStack { caption("LENGTH"); Spacer(); Text(String(format: "%.2f beats", note.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                Slider(value: Binding(get: { currentNote?.duration ?? note.duration }, set: { state.setNoteDuration(trackID: track.id, noteID: note.id, duration: $0) }), in: 0.25...max(0.25, state.project.patternBeats - note.beat), step: 0.25)
                    .accessibilityLabel("Selected note length").accessibilityIdentifier("noteLengthSlider")
            }
            .frame(minWidth: 135, maxWidth: 200)
            VStack(alignment: .leading, spacing: 3) {
                HStack { caption("VELOCITY"); Spacer(); Text("\(Int(note.velocity * 100))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
                Slider(value: Binding(get: { currentNote?.velocity ?? note.velocity }, set: { state.setNoteVelocity(trackID: track.id, noteID: note.id, velocity: $0) }), in: 0.01...1)
                    .accessibilityLabel("Selected note velocity").accessibilityIdentifier("noteVelocitySlider")
            }
            .frame(minWidth: 100, maxWidth: 165)
            Spacer(minLength: 0)
            Button(role: .destructive) {
                state.edit { project in
                    if let index = project.tracks.firstIndex(where: { $0.id == track.id }) { project.tracks[index].notes.removeAll { $0.id == note.id } }
                }
                onDelete()
            } label: { Label("Delete", systemImage: "trash") }
            .accessibilityIdentifier("deleteNoteButton")
        }
        .controlSize(.small).padding(.horizontal, 18).frame(height: 72)
        .background(.thinMaterial)
    }

    private var currentNote: NoteEvent? { state.project.tracks.first(where: { $0.id == track.id })?.notes.first(where: { $0.id == note.id }) }
    private func caption(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary) }
    private var pitchBinding: Binding<Int> {
        Binding(get: { currentNote?.midiNote ?? note.midiNote }, set: { pitch in change { $0.midiNote = pitch } })
    }
    private var startBinding: Binding<Double> {
        Binding(get: { currentNote?.beat ?? note.beat }, set: { beat in change { note in
            note.beat = beat; note.duration = min(note.duration, state.project.patternBeats - beat)
        } })
    }
    private func change(_ transform: (inout NoteEvent) -> Void) {
        state.edit { project in
            guard let trackIndex = project.tracks.firstIndex(where: { $0.id == track.id }), let noteIndex = project.tracks[trackIndex].notes.firstIndex(where: { $0.id == note.id }) else { return }
            transform(&project.tracks[trackIndex].notes[noteIndex])
        }
    }
}
