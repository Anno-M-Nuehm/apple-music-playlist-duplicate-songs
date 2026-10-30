import AppKit
import SwiftUI

/// Menu that shows the active Music library and lets the user choose a
/// different `.musiclibrary` file, or revert to the currently open one.
struct LibraryPickerButton: View {
    @Environment(LibraryViewModel.self) private var library
    let onPick: (URL?) -> Void

    var body: some View {
        Menu {
            Button("Current Music Library") { onPick(nil) }
            Button("Choose Library…") { chooseLibrary() }
            if let selected = library.selectedLibraryURL {
                Divider()
                Button("Use “\(selected.deletingPathExtension().lastPathComponent)”") {
                    onPick(selected)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "music.note.house")
                Text(library.selectedLibraryName ?? "Music Library")
                    .lineLimit(1)
            }
        }
        .help("Choose which Apple Music Library to analyze")
    }

    /// NSOpenPanel (not fileImporter): `.musiclibrary` is a package
    /// (directory bundle), which SwiftUI's fileImporter cannot select.
    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Choose an Apple Music Library file (.musiclibrary)"
        let musicDir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        panel.directoryURL = musicDir
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            onPick(url)
        }
    }
}
