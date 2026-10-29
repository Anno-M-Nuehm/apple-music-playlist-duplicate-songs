import SwiftUI

/// Quick-start steps, also reachable from the Help menu.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Quick Start").font(.title2.bold())
                Text(quickStart).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("How to export a duplicate report").font(.title2.bold())
                Text(exportGuide).fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
            .frame(maxWidth: 620)
        }
    }

    var quickStart: String {
        """
        1. Open Music. The first time, macOS asks for permission to control Music — click OK.
        2. Playlist Deduplicator scans your playlists and flags those containing duplicates in the middle pane.
        3. Click a flagged playlist; its duplicate groups appear on the right, with all but the first occurrence pre-selected for removal.
        4. Review the pre-selection (uncheck any entry you want to keep), then click “Remove Selected”.
        5. Only entries inside the selected playlist are removed — never files, never other playlists.
        """
    }

    var exportGuide: String {
        """
        1. Select a playlist with duplicates.
        2. Choose File ▸ Export Report… (⇧⌘E).
        3. Pick CSV (spreadsheet-friendly) or Markdown (readable).
        4. Choose a location — the report lists every duplicate group, all occurrences, and which entries were flagged for removal.
        """
    }
}
