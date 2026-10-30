import Foundation
import ScriptingBridge

/// Real Music integration via ScriptingBridge — pure Swift, no
/// AppleScript source text, no Python.
///
/// - Fetches read typed properties through SB objects; no strings are
///   ever compiled or executed, so there is no script-injection surface
///   at all.
/// - `SBElementArray` mutating methods send Music's own commands:
///   `addObject` maps to `duplicate`, `removeObject(at:)` maps to
///   `delete` for the element at that index. Deleting an element of a
///   playlist's `tracks` array removes that playlist entry only —
///   never the file, never another playlist.
/// - All work runs on a serial queue; the UI never blocks.
final class ScriptingBridgeMusicService: MusicLibraryService, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.example.PlaylistDeduplicator.scriptingbridge")
    private var activeLibraryPath: String?
    private(set) var lastError: MusicServiceError?

    private func musicApp() throws -> MusicApplicationProtocol {
        guard let app = SBApplication(bundleIdentifier: Constants.App.musicAppBundleID) as? MusicApplicationProtocol else {
            throw MusicServiceError(code: .musicNotRunning, message: "Music is not installed or cannot be launched")
        }
        return app
    }

    private func playlist(for id: UInt64, in app: MusicApplicationProtocol) throws -> MusicPlaylistProtocol {
        let array = app.playlists
        let count = array?.count ?? 0
        for index in 0..<count {
            if let playlist = array?.object(at: index) as? MusicPlaylistProtocol,
               playlist.id == Int(id) {
                return playlist
            }
        }
        throw MusicServiceError(code: .safetyCheckFailed, message: "Playlist not found")
    }

    func ensureAccess() async throws {
        try await queue.run { [self] in
            let app = try musicApp()
            guard app.name != nil else {
                throw MusicServiceError(code: .musicNotRunning, message: "Music did not respond")
            }
        }
    }

    func useLibrary(at url: URL?) async throws {
        guard let url else { return }
        let path = url.path
        if path == activeLibraryPath {
            try await ensureAccess()
            return
        }
        try await queue.run { [self] in
            let app = try musicApp()
            app.open?([url])
        }
        try await waitForMusicReady()
        activeLibraryPath = path
    }

    private func waitForMusicReady() async throws {
        for _ in 0..<30 {
            do {
                try await ensureAccess()
                return
            } catch {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw MusicServiceError(code: .musicNotRunning, message: "Music did not respond after switching libraries")
    }

    func fetchPlaylists() async throws -> [Playlist] {
        try await queue.run { [self] in
            let app = try musicApp()
            let array = app.playlists
            var result: [Playlist] = []
            let count = array?.count ?? 0
            for index in 0..<count {
                guard let playlist = array?.object(at: index) as? MusicPlaylistProtocol else { continue }
                result.append(Playlist(
                    id: UInt64(playlist.id),
                    name: playlist.name ?? "",
                    trackCount: playlist.tracks?.count ?? 0,
                    isSmart: playlist.smart
                ))
            }
            return result
        }
    }

    func fetchEntries(playlistID: UInt64) async throws -> [PlaylistEntry] {
        try await queue.run { [self] in
            let app = try musicApp()
            let playlist = try playlist(for: playlistID, in: app)
            let tracks = playlist.tracks
            var entries: [PlaylistEntry] = []
            let count = tracks?.count ?? 0
            for index in 0..<count {
                guard let track = tracks?.object(at: index) as? MusicTrackProtocol else { continue }
                entries.append(PlaylistEntry(
                    playlistID: playlistID,
                    index: index + 1,
                    track: Track(
                        persistentID: Self.parsePersistentID(track.persistentID),
                        title: track.name ?? "",
                        artist: track.artist ?? "",
                        album: track.album ?? "",
                        duration: track.duration,
                        location: track.location
                    )
                ))
            }
            return entries
        }
    }

    func removeEntries(playlistID: UInt64, indexes: [Int]) async throws {
        try await queue.run { [self] in
            let app = try musicApp()
            let playlist = try playlist(for: playlistID, in: app)
            let tracks = playlist.tracks
            let count = tracks?.count ?? 0
            let sorted = Set(indexes).sorted(by: >)
            guard !sorted.isEmpty,
                  sorted.allSatisfy({ (1...max(count, 1)).contains($0) }) else {
                throw MusicServiceError(code: .safetyCheckFailed, message: "Index out of range")
            }
            // Descending: removing index i shifts only later elements.
            for index in sorted {
                tracks?.removeObject(at: index - 1)
            }
            let newCount = playlist.tracks?.count ?? 0
            guard newCount == count - sorted.count else {
                throw MusicServiceError(code: .safetyCheckFailed,
                                        message: "Playlist changed during removal (\(count) → \(newCount), expected \(count - sorted.count))")
            }
        }
    }

    private static func parsePersistentID(_ raw: String?) -> UInt64 {
        guard let raw else { return 0 }
        return UInt64(raw, radix: Constants.Track.persistentIDRadix)
            ?? UInt64(raw)
            ?? raw.hashValue.magnitude
    }
}

private extension DispatchQueue {
    func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}
