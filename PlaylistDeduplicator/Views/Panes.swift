import SwiftUI

/// Pane 1: all playlists.
struct PlaylistsPane: View {
    @Environment(LibraryViewModel.self) private var library
    @Binding var selectedPlaylist: Playlist?

    var body: some View {
        List(library.playlists, selection: Binding(
            get: { selectedPlaylist?.id },
            set: { newValue in
                selectedPlaylist = library.playlists.first { $0.id == newValue }
            }
        )) { playlist in
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundStyle(.secondary)
                Text(playlist.name)
                Spacer()
                Text("\(playlist.trackCount)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .tag(playlist.id)
        }
        .overlay {
            if library.isLoading { ProgressView() }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = library.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).padding(6)
            }
        }
    }
}

/// Pane 2: playlists that contain duplicates, with a count badge.
struct DuplicatesBadgePane: View {
    @Environment(LibraryViewModel.self) private var library
    @Binding var selectedPlaylist: Playlist?

    var body: some View {
        List(library.playlistsWithDuplicates, selection: Binding(
            get: { selectedPlaylist?.id },
            set: { newValue in
                selectedPlaylist = library.playlists.first { $0.id == newValue }
            }
        )) { playlist in
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(playlist.name)
                Spacer()
                Text("\(library.duplicateCounts[playlist.id] ?? 0)")
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.red.opacity(0.85), in: Capsule())
                    .font(.callout.bold())
                    .foregroundStyle(.white)
            }
            .tag(playlist.id)
        }
        .overlay {
            if library.playlists.isEmpty && !library.isLoading {
                ContentUnavailableView("No duplicates", systemImage: "checkmark.circle",
                                      description: Text("No playlist contains duplicates."))
            }
        }
    }
}

/// Pane 3: duplicate groups of the selected playlist, grouped by track.
struct DuplicateGroupsPane: View {
    @Environment(DuplicationViewModel.self) private var duplication

    var body: some View {
        Group {
            if duplication.groups.isEmpty {
                ContentUnavailableView(duplication.isLoading ? "Loading…" : "No duplicates",
                                        systemImage: "sparkles",
                                        description: Text("Select a playlist flagged in the middle pane."))
            } else {
                List {
                    ForEach(duplication.groups) { group in
                        DuplicateGroupRow(group: group)
                    }
                    Section {
                        Button("Remove Selected (\(duplication.selectedCount))") {
                            Task { await duplication.removeSelected() }
                        }
                        .keyboardShortcut(.return)
                        .disabled(duplication.selectedCount == 0 || duplication.isRemoving)
                        if duplication.isRemoving { ProgressView() }
                    }
                    if let error = duplication.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DuplicateGroupRow: View {
    @Environment(DuplicationViewModel.self) private var duplication
    let group: DuplicateGroup

    var body: some View {
        Section("\(group.keep.track.title) — \(group.keep.track.artist)") {
            ForEach(group.entries) { entry in
                HStack {
                    Image(systemName: entry.id == group.keep.id ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundStyle(entry.id == group.keep.id ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(entry.track.title)
                        Text("\(entry.track.artist) • \(entry.track.album) • \(Int(entry.track.duration))s")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("#\(entry.index)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Toggle("Remove", isOn: Binding(
                        get: { duplication.selectedForRemoval.contains(entry.id) },
                        set: { _ in duplication.toggle(entry) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(entry.id == group.keep.id)
                }
            }
            HStack {
                Button("Select all but first") { duplication.selectAllRemovals(in: group) }
                Button("None") { duplication.clearRemovals(in: group) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}
