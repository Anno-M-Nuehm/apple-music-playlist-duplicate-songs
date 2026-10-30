import SwiftUI

/// Root three-pane interface:
/// 1. All playlists
/// 2. Playlists with duplicates (badge with count)
/// 3. Duplicates in the selected playlist, grouped by track
struct ContentView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(DuplicationViewModel.self) private var duplication
    @State private var selectedPlaylist: Playlist?
    @State private var exportRequested = false

    var body: some View {
        HSplitView {
            PlaylistsPane(selectedPlaylist: $selectedPlaylist)
                .frame(minWidth: 220, idealWidth: 260)
            DuplicatesBadgePane(selectedPlaylist: $selectedPlaylist)
                .frame(minWidth: 220, idealWidth: 260)
            DuplicateGroupsPane()
                .frame(minWidth: 420)
        }
        .frame(minWidth: 900, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await library.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Reload playlists from the current Music Library")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Export Report…") { exportRequested = true }
                    .keyboardShortcut("e")
                    .disabled(selectedPlaylist == nil || duplication.groups.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                LibraryPickerButton { url in
                    library.selectedLibraryURL = url
                    Task { await library.load() }
                }
            }
        }
        .navigationTitle("Playlist Deduplicator")
        .sheet(isPresented: $exportRequested) {
            if let playlist = selectedPlaylist {
                ExportSheet(playlist: playlist)
            }
        }
        .task { await library.load() }
        .onChange(of: selectedPlaylist) { _, playlist in
            if let playlist { Task { await duplication.load(playlist: playlist) } }
        }
    }
}

#Preview {
    ContentView()
        .environment(LibraryViewModel(service: MockMusicService.sample))
        .environment(DuplicationViewModel(service: MockMusicService.sample))
}
