import Foundation

/// A track in the Music library. Only properties relevant to
/// duplicate detection and reporting are modelled.
struct Track: Identifiable, Hashable, Sendable {
    var persistentID: UInt64
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var location: URL?

    var id: UInt64 { persistentID }

    var hasValidLocation: Bool {
        guard let location else { return false }
        return !location.path.isEmpty
    }

    /// Normalized key used by the metadata-based fallback matcher.
    var metadataKey: String {
        "\(title.trimmedAndLowercased)|\(artist.trimmedAndLowercased)|\(album.trimmedAndLowercased)"
    }
}

extension String {
    var trimmedAndLowercased: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
