import AppKit
import SwiftUI
import VLCore

final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState? {
        didSet {
            guard state != nil, let url = pendingURL else { return }
            pendingURL = nil
            MainActor.assumeIsolated { state?.openProject(at: url) }
        }
    }
    private var pendingURL: URL?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { state?.confirmDiscard() == false ? .terminateCancel : .terminateNow }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated {
            if let state { state.openProject(at: url) }
            else { pendingURL = url }
        }
    }
}

@main
struct VLStudioApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var delegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("Veggie Loops") {
            StudioView(state: state)
                .frame(minWidth: 1050, minHeight: 720)
                .onAppear { delegate.state = state }
                .alert("VL Studio", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
                    Button("OK", role: .cancel) { state.errorMessage = nil }
                } message: { Text(state.errorMessage ?? "") }
        }
        .defaultSize(width: 1320, height: 850)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { state.newProject() }.keyboardShortcut("n")
                Button("Open Project…") { state.openProject() }.keyboardShortcut("o")
                Button("Load Demo Groove") { state.loadDemo() }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Project") { state.saveProject() }.keyboardShortcut("s")
                Button("Save Project As…") { state.saveProjectAs() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Export WAV…") { state.exportWAV() }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(state.isExporting)
                Button("Import Sample…") { state.importSample() }.keyboardShortcut("i")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { state.undo() }.keyboardShortcut("z").disabled(!state.canUndo)
                Button("Redo") { state.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!state.canRedo)
            }
            CommandMenu("Transport") {
                Button(state.isPlaying ? "Stop" : "Play") { state.togglePlayback() }.keyboardShortcut(.space, modifiers: [])
                Button("Return to Start") { state.stopPlayback() }.keyboardShortcut(".", modifiers: [])
                Divider()
                Button("Pattern Mode") { state.changeMode(.pattern) }
                Button("Song Mode") { state.changeMode(.song) }
            }
            CommandMenu("Editors") {
                Button("Channel Rack") { state.editor = .sequencer }.keyboardShortcut("1")
                Button("Piano Roll") { state.editor = .pianoRoll }.keyboardShortcut("2")
                Button("Arrangement") { state.editor = .arrangement }.keyboardShortcut("3")
            }
        }
    }
}
