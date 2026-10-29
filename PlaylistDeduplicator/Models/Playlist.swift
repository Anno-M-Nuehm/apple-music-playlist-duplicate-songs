import Foundation

/// A user playlist in the Music library.
struct Playlist: Identifiable, Hashable, Sendable {
    var id: UInt64
    var name: String
    var trackCount: Int
    var isSmart: Bool
}

/// One occurrence of a track inside a specific playlist.
/// `index` is the 1-based position of the entry in the playlist.
/// This identifies the *entry*, not the track: the same track
/// appearing twice has two entries with the same `track`.
struct PlaylistEntry: Identifiable, Hashable, Sendable {
    var playlistID: UInt64
    var index: Int
    var track: Track

    var id: String { "\(playlistID)#\(index)" }
}

/// A group of playlist entries that are duplicates of each other.
/// `keep` is the occurrence that stays (by convention the first),
/// `remove` contains all others.
struct DuplicateGroup: Identifiable, Hashable, Sendable {
    var keep: PlaylistEntry
    var removals: [PlaylistEntry]

    var entries: [PlaylistEntry] { [keep] + removals }
    var id: String { keep.id }
}
