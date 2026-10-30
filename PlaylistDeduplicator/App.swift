import SwiftUI

@main
struct PlaylistDeduplicatorApp: App {
    @State private var library: LibraryViewModel
    @State private var duplication: DuplicationViewModel

    init() {
        let musicService = ScriptingBridgeMusicService()
        let config = ConfigStore.load()
        _library = State(initialValue: LibraryViewModel(service: musicService, config: config))
        _duplication = State(initialValue: DuplicationViewModel(service: musicService, config: config))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(duplication)
        }
        .commands { PlaylistDeduplicatorCommands() }
        Window("Help", id: "help") { HelpView() }
            .windowResizability(.contentSize)
            .defaultSize(width: 640, height: 520)
    }
}

/// Help menu with quick-start steps and the report-export guide.
struct PlaylistDeduplicatorCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Playlist Deduplicator Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
