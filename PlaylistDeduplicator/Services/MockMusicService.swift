import Foundation

/// Mock Music layer used in previews and integration tests.
final class MockMusicService: MusicLibraryService, @unchecked Sendable {
    var playlists: [Playlist]
    var entries: [UInt64: [PlaylistEntry]]
    var removalLog: [(playlistID: UInt64, indexes: [Int])] = []
    var fetchError: MusicServiceError?
    var removeError: MusicServiceError?

    private let lock = NSLock()

    init(playlists: [Playlist], entries: [UInt64: [PlaylistEntry]]) {
        self.playlists = playlists
        self.entries = entries
    }

    static var sample: MockMusicService {
        let p = Playlist(id: 1, name: "Road Trip", trackCount: 4, isSmart: false)
        let t = Track(persistentID: 100, title: "Song A", artist: "Artist X", album: "Album Y", duration: 200, location: nil)
        let entries = [
            PlaylistEntry(playlistID: 1, index: 1, track: t),
            PlaylistEntry(playlistID: 1, index: 2, track: t),
            PlaylistEntry(playlistID: 1, index: 3, track: Track(persistentID: 101, title: "Song B", artist: "Artist X", album: "Album Y", duration: 180, location: nil))
        ]
        return MockMusicService(playlists: [p], entries: [1: entries])
    }

    func ensureAccess() async throws {}

    func fetchPlaylists() async throws -> [Playlist] {
        if let fetchError { throw fetchError }
        return lock.withLock { playlists }
    }

    func fetchEntries(playlistID: UInt64) async throws -> [PlaylistEntry] {
        if let fetchError { throw fetchError }
        return lock.withLock { entries[playlistID] ?? [] }
    }

    func removeEntries(playlistID: UInt64, indexes: [Int]) async throws {
        if let removeError { throw removeError }
        lock.withLock {
            removalLog.append((playlistID, indexes))
            var current = entries[playlistID] ?? []
            for index in indexes.sorted(by: >) where (1...current.count).contains(index) {
                current.remove(at: index - 1)
            }
            entries[playlistID] = current
        }
    }

    var lastError: MusicServiceError? { nil }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
