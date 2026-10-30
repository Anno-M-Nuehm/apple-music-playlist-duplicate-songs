import AppKit
import Foundation
import ScriptingBridge

/// Real Music integration via ScriptingBridge — pure Swift, no
/// AppleScript source text, no Python.
///
/// Uses the standard sdp-generated interface in Generated/Music.h
/// (bridged through MusicScripting.h). All calls are typed; SBObject's
/// documented method resolution handles everything — no dynamic
/// `perform(Selector(...))` (which crashes: SB returns non-object
/// descriptors that Swift retains as garbage pointers) and no
/// hand-written @objc protocol casts (which fail: SB objects don't
/// declare conformance).
///
/// - SBApplication/SBObject are not thread-safe: every call runs on
///   the main actor.
/// - Removal uses `SBElementArray.removeObject(at:)` on the selected
///   playlist's tracks — Music's native delete for that element. It
///   removes a playlist entry only: never the file, never another
///   playlist. A count check after removal verifies the result.
final class ScriptingBridgeMusicService: MusicLibraryService, @unchecked Sendable {
    private var activeLibraryPath: String?
    private(set) var lastError: MusicServiceError?

    private func musicApp() throws -> MusicApplication {
        if let app = Self.resolveMusicApp() {
            return app
        }
        throw MusicServiceError(code: .musicNotRunning, message: "Music is not installed or cannot be launched")
    }

    /// SBApplication instances are always the base SBApplication class;
    /// generated-header subclasses are a compile-time lens only (ObjC
    /// never downcasts — it relies on SBObject's dynamic method
    /// forwarding). Swift's `as?` performs a real runtime class check and
    /// always fails, so the typed view is created with unsafeBitCast:
    /// identical object, identical runtime behavior, typed accessors.
    private static func typed(_ app: SBApplication) -> MusicApplication {
        unsafeBitCast(app, to: MusicApplication.self)
    }

    private static func resolveMusicApp() -> MusicApplication? {
        if let app = SBApplication(bundleIdentifier: Constants.App.musicAppBundleID) {
            return typed(app)
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Constants.App.musicAppBundleID).first,
           let url = running.bundleURL,
           let app = SBApplication(url: url) {
            return typed(app)
        }
        for path in ["/System/Applications/Music.app", "/Applications/Music.app"]
        where FileManager.default.fileExists(atPath: path) {
            if let app = SBApplication(url: URL(fileURLWithPath: path)) {
                return typed(app)
            }
        }
        return nil
    }

    private func userPlaylists(in app: MusicApplication) throws -> SBElementArray {
        guard let playlists = app.userPlaylists else {
            throw MusicServiceError(code: .scriptFailed("userPlaylists"), message: "Music returned no user playlists")
        }
        return playlists
    }

    private func playlistObject(id: UInt64, in app: MusicApplication) throws -> MusicUserPlaylist {
        let playlists = try userPlaylists(in: app)
        for index in 0..<playlists.count {
            if let object = playlists.object(at: index) as? NSObject {
                let playlist = unsafeBitCast(object, to: MusicUserPlaylist.self)
                if playlist.id == Int(id) {
                    return playlist
                }
            }
        }
        throw MusicServiceError(code: .safetyCheckFailed, message: "Playlist not found")
    }

    func ensureAccess() async throws {
        try await MainActor.run { [self] in
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
        try await MainActor.run { [self] in
            let app = try musicApp()
            app.open([url])
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
        try await MainActor.run { [self] in
            let app = try musicApp()
            let playlists = try userPlaylists(in: app)
            var result: [Playlist] = []
            for index in 0..<playlists.count {
                guard let object = playlists.object(at: index) as? NSObject else { continue }
                let playlist = unsafeBitCast(object, to: MusicUserPlaylist.self)
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
        try await MainActor.run { [self] in
            let app = try musicApp()
            let playlist = try playlistObject(id: playlistID, in: app)
            guard let tracks = playlist.tracks else {
                throw MusicServiceError(code: .scriptFailed("tracks"), message: "Playlist returned no tracks")
            }
            var entries: [PlaylistEntry] = []
            for index in 0..<tracks.count {
                guard let object = tracks.object(at: index) as? NSObject else { continue }
                let track = unsafeBitCast(object, to: MusicTrack.self)
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
        try await MainActor.run { [self] in
            let app = try musicApp()
            let playlist = try playlistObject(id: playlistID, in: app)
            guard let tracks = playlist.tracks else {
                throw MusicServiceError(code: .scriptFailed("tracks"), message: "Playlist returned no tracks")
            }
            let count = tracks.count
            let sorted = Set(indexes).sorted(by: >)
            guard !sorted.isEmpty,
                  sorted.allSatisfy({ (1...max(count, 1)).contains($0) }) else {
                throw MusicServiceError(code: .safetyCheckFailed, message: "Index out of range")
            }
            // Descending: removing index i shifts only later elements.
            for index in sorted {
                tracks.removeObject(at: index - 1)
            }
            let newCount = playlist.tracks?.count ?? count
            guard newCount == count - sorted.count else {
                throw MusicServiceError(code: .safetyCheckFailed,
                                        message: "Playlist changed during removal (\(count) → \(newCount), expected \(count - sorted.count))")
            }
        }
    }

    private static func parsePersistentID(_ raw: String?) -> UInt64 {
        guard let raw, !raw.isEmpty else { return 0 }
        return UInt64(raw, radix: Constants.Track.persistentIDRadix)
            ?? UInt64(raw)
            ?? UInt64(abs(raw.hashValue))
    }
}
