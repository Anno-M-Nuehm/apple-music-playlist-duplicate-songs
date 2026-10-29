import AppKit
import SwiftUI

/// Menu that shows the active Music library and lets the user choose a
/// different `.musiclibrary` file, or revert to the currently open one.
struct LibraryPickerButton: View {
    @Environment(LibraryViewModel.self) private var library
    let onPick: (URL?) -> Void

    @State private var isPresentingPicker = false

    var body: some View {
        Menu {
            Button("Current Music Library") { onPick(nil) }
            Button("Choose Library…") { isPresentingPicker = true }
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
        .fileImporter(isPresented: $isPresentingPicker,
                      allowedContentTypes: [.init(filenameExtension: Constants.Library.fileExtension, conformingTo: .data)!],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            onPick(url)
        }
        .help("Choose which Apple Music Library to analyze")
    }
}
