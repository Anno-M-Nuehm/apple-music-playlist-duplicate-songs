import Foundation

/// Abstraction over the Music app scripting layer, so it can be
/// mocked in tests and UI previews.
///
/// All methods are asynchronous and safe to call from any executor.
protocol MusicLibraryService: Sendable {
    /// Whether Music is running and scriptable (launched if needed).
    func ensureAccess() async throws

    /// All user playlists, batched fetch.
    func fetchPlaylists() async throws -> [Playlist]

    /// Track metadata for one playlist, batched fetch.
    /// Returns 1-based-indexed entries matching the playlist order.
    func fetchEntries(playlistID: UInt64) async throws -> [PlaylistEntry]

    /// Removes the entries at the given 1-based indexes from the
    /// given playlist ONLY. Verifies the playlist track count before
    /// and after; aborts without changes on mismatch.
    func removeEntries(playlistID: UInt64, indexes: [Int]) async throws

    var lastError: MusicServiceError? { get }
}

struct MusicServiceError: Error, Equatable, Sendable {
    enum Code: Equatable, Sendable {
        case notAuthorized
        case musicNotRunning
        case scriptFailed(String)
        case safetyCheckFailed
    }

    var code: Code
    var message: String
}
