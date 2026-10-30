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

    /// Every playlist (user, smart, folder-nested). `userPlaylists` in
    /// Music's dictionary omits smart and folder-nested playlists, so the
    /// broader `playlists` element is used and special sources are
    /// filtered by `specialKind` below.
    private func allPlaylists(in app: MusicApplication) throws -> SBElementArray {
        guard let playlists = app.playlists else {
            throw MusicServiceError(code: .scriptFailed("playlists"), message: "Music returned no playlists")
        }
        return playlists
    }

    private func isOrdinary(_ playlist: MusicPlaylist) -> Bool {
        Constants.MusicScripting.specialKindNoneValues.contains(playlist.specialKind)
    }

    private func playlistObject(id: UInt64, in app: MusicApplication) throws -> MusicUserPlaylist {
        let playlists = try allPlaylists(in: app)
        for index in 0..<playlists.count {
            if let object = playlists.object(at: index) as? NSObject {
                let playlist = unsafeBitCast(object, to: MusicPlaylist.self)
                if isOrdinary(playlist), playlist.id == Int(id) {
                    return unsafeBitCast(object, to: MusicUserPlaylist.self)
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
        // Open the library document through NSWorkspace (Finder path):
        // Music's SB forwarding does not implement the `open` command
        // (raises an ObjC exception Swift cannot catch). NSWorkspace
        // launches Music with the chosen library if needed.
        try await MainActor.run { [self] in
            guard NSWorkspace.shared.open(url) else {
                throw MusicServiceError(code: .musicNotRunning, message: "Could not open library at \(path)")
            }
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
            let elementArray = try allPlaylists(in: app)
            // Per-index iteration: the `playlists` element includes the
            // huge library sources, so a batched get() over it blocks.
            // Index access sends a small, bounded event per playlist.
            var result: [Playlist] = []
            for index in 0..<elementArray.count {
                guard let object = elementArray.object(at: index) as? NSObject else { continue }
                let playlist = unsafeBitCast(object, to: MusicPlaylist.self)
                guard isOrdinary(playlist) else { continue }
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
            // Bulk fetch: ONE Apple event for every track's metadata.
            // Per-property SB reads cost an Apple event per track per
            // property — minutes on large playlists. A plain NSAppleScript
            // (no `on run` handler, so executeAndReturnError runs it
            // directly) builds a delimited record stream in a single
            // event. The script text embeds ONLY the playlist's
            // validated numeric id — never user data — so there is no
            // injection surface.
            let id = Int(playlistID)
            let source = """
                on safeText(v)
                    try
                        return v as text
                    on error
                        return ""
                    end try
                end safeText

                tell application "Music"
                    set fieldSep to ASCII character 1
                    set recordSep to ASCII character 2
                    set target to first playlist whose id is \(id)
                    set output to ""
                    repeat with t in (every track of target)
                        set output to output & (my safeText(persistent ID of t)) & fieldSep & (my safeText(name of t)) & fieldSep & (my safeText(artist of t)) & fieldSep & (my safeText(album of t)) & fieldSep & (my safeText(duration of t as text)) & recordSep
                    end repeat
                    return output
                end tell
                """
            guard let script = NSAppleScript(source: source) else {
                throw MusicServiceError(code: .scriptFailed("init"), message: "Could not create bulk fetch script")
            }
            var error: NSDictionary?
            let reply = script.executeAndReturnError(&error)
            guard error == nil else { throw Self.bulkFetchError(error) }
            let output = reply.stringValue ?? ""
            var entries: [PlaylistEntry] = []
            for (position, record) in output.split(separator: "\u{2}", omittingEmptySubsequences: true).enumerated() {
                let fields = record.split(separator: "\u{1}", omittingEmptySubsequences: false)
                guard fields.count == 5 else { continue }
                let rawID = String(fields[0])
                let persistentID = Self.parsePersistentID(rawID)
                entries.append(PlaylistEntry(
                    playlistID: playlistID,
                    index: position + 1,
                    track: Track(
                        persistentID: persistentID != 0 ? persistentID : Self.nextSyntheticID(),
                        title: String(fields[1]),
                        artist: String(fields[2]),
                        album: String(fields[3]),
                        duration: Double(fields[4]) ?? 0,
                        location: nil
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
            guard let elementArray = playlist.tracks else {
                throw MusicServiceError(code: .scriptFailed("tracks"), message: "Playlist returned no tracks")
            }
            let count = elementArray.count
            let sorted = Set(indexes).sorted(by: >)
            guard !sorted.isEmpty,
                  sorted.allSatisfy({ (1...max(count, 1)).contains($0) }) else {
                throw MusicServiceError(code: .safetyCheckFailed, message: "Index out of range")
            }
            // Descending: removing index i shifts only later elements.
            for index in sorted {
                elementArray.removeObject(at: index - 1)
            }
            let newCount = playlist.tracks?.count ?? count
            guard newCount == count - sorted.count else {
                throw MusicServiceError(code: .safetyCheckFailed,
                                        message: "Playlist changed during removal (\(count) → \(newCount), expected \(count - sorted.count))")
            }
        }
    }

    private static func bulkFetchError(_ error: NSDictionary?) -> MusicServiceError {
        let number = (error?.value(forKey: NSAppleScript.errorNumber) as? Int).map(String.init) ?? "?"
        let message = (error?.value(forKey: NSAppleScript.errorMessage) as? String) ?? "AppleScript error"
        return MusicServiceError(code: .scriptFailed(number), message: message)
    }

    /// Music persistent IDs are hex strings ("A1B2C3..."). If parsing
    /// fails, the track gets a unique synthetic ID so it can never be
    /// grouped with another track by mistake — a fabricated or colliding
    /// ID would create phantom duplicate groups.
    private static func parsePersistentID(_ raw: String?) -> UInt64 {
        guard let raw, !raw.isEmpty,
              let parsed = UInt64(raw, radix: Constants.Track.persistentIDRadix) else {
            return 0
        }
        return parsed
    }

    private static var syntheticIDCounter: UInt64 = 0
    /// Unique non-zero ID for tracks without a parseable persistent ID.
    private static func nextSyntheticID() -> UInt64 {
        syntheticIDCounter &+= 1
        return syntheticIDCounter
    }
}
