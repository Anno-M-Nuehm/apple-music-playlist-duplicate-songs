import AppKit
import Foundation
import ScriptingBridge

/// Real Music integration via ScriptingBridge — pure Swift, no
/// AppleScript source text, no Python.
///
/// Without a generated scripting header, ScriptingBridge property
/// access goes through `perform(Selector(...))`: SBObject resolves
/// unknown selectors dynamically against the application's sdef
/// (that is ScriptingBridge's built-in dispatch mechanism). Casting an
/// SBApplication to a hand-written @objc protocol does NOT work —
/// runtime protocol conformance is not dynamic — so selectors are used
/// directly instead.
///
/// - Reads send Music's native `get` events; only typed values cross
///   the boundary. No string is ever compiled or executed, so there is
///   no script-injection surface at all.
/// - Removal uses `SBElementArray.removeObject(at:)` on the selected
///   playlist's `tracks` array — Music's native delete for that
///   element. It removes a playlist entry only: never the file, never
///   another playlist. A count check after removal verifies the result.
/// - All work runs on a serial queue; the UI never blocks.
final class ScriptingBridgeMusicService: MusicLibraryService, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.example.PlaylistDeduplicator.scriptingbridge")
    private var activeLibraryPath: String?
    private(set) var lastError: MusicServiceError?

    // MARK: - App resolution

    private func musicApp() throws -> SBApplication {
        if let app = Self.resolveMusicApp() {
            return app
        }
        throw MusicServiceError(code: .musicNotRunning, message: "Music is not installed or cannot be launched")
    }

    /// SBApplication(bundleIdentifier:) returns nil for system apps on
    /// some macOS versions; resolve the app from the running process or
    /// its bundle URL instead.
    private static func resolveMusicApp() -> SBApplication? {
        if let app = SBApplication(bundleIdentifier: Constants.App.musicAppBundleID) {
            return app
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Constants.App.musicAppBundleID).first,
           let url = running.bundleURL {
            return SBApplication(url: url)
        }
        for path in ["/System/Applications/Music.app", "/Applications/Music.app"]
        where FileManager.default.fileExists(atPath: path) {
            return SBApplication(url: URL(fileURLWithPath: path))
        }
        return nil
    }

    // MARK: - Dynamic property access

    /// Sends the property-getter Apple event for `name` and returns the
    /// resulting value, or nil.
    @discardableResult
    private static func value(_ object: NSObject, _ name: String) -> Any? {
        object.perform(Selector(name))?.takeUnretainedValue()
    }

    private static func string(_ object: NSObject, _ name: String) -> String? {
        value(object, name) as? String
    }

    private static func int(_ object: NSObject, _ name: String) -> Int? {
        if let number = value(object, name) as? NSNumber { return number.intValue }
        if let text = value(object, name) as? String { return Int(text) }
        return nil
    }

    private static func double(_ object: NSObject, _ name: String) -> Double? {
        if let number = value(object, name) as? NSNumber { return number.doubleValue }
        if let text = value(object, name) as? String { return Double(text) }
        return nil
    }

    private static func bool(_ object: NSObject, _ name: String) -> Bool {
        if let number = value(object, name) as? NSNumber { return number.boolValue }
        if let text = value(object, name) as? String { return text == "true" }
        return false
    }

    private static func elementArray(_ object: NSObject, _ name: String) -> SBElementArray? {
        value(object, name) as? SBElementArray
    }

    // MARK: - MusicLibraryService

    func ensureAccess() async throws {
        try await queue.run { [self] in
            let app = try musicApp()
            guard Self.string(app, "name") != nil else {
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
            _ = app.perform(Selector("open:"), with: url as NSURL)?.takeUnretainedValue()
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
            guard let playlists = Self.elementArray(app, "playlists") else {
                throw MusicServiceError(code: .scriptFailed("playlists"), message: "Music returned no playlists element")
            }
            var result: [Playlist] = []
            for index in 0..<playlists.count {
                guard let playlist = playlists.object(at: index) as? NSObject else { continue }
                result.append(Playlist(
                    id: UInt64(Self.int(playlist, "id") ?? 0),
                    name: Self.string(playlist, "name") ?? "",
                    trackCount: Self.elementArray(playlist, "tracks")?.count ?? 0,
                    isSmart: Self.bool(playlist, "smart")
                ))
            }
            return result
        }
    }

    func fetchEntries(playlistID: UInt64) async throws -> [PlaylistEntry] {
        try await queue.run { [self] in
            let app = try musicApp()
            let playlist = try playlistObject(id: playlistID, in: app)
            let tracks = try Self.elementArray(playlist, "tracks") ?? {
                throw MusicServiceError(code: .scriptFailed("tracks"), message: "Playlist returned no tracks element")
            }()
            var entries: [PlaylistEntry] = []
            for index in 0..<tracks.count {
                guard let track = tracks.object(at: index) as? NSObject else { continue }
                entries.append(PlaylistEntry(
                    playlistID: playlistID,
                    index: index + 1,
                    track: Track(
                        persistentID: Self.parsePersistentID(Self.string(track, "persistentID")),
                        title: Self.string(track, "name") ?? "",
                        artist: Self.string(track, "artist") ?? "",
                        album: Self.string(track, "album") ?? "",
                        duration: Self.double(track, "duration") ?? 0,
                        location: Self.value(track, "location") as? URL
                    )
                ))
            }
            return entries
        }
    }

    func removeEntries(playlistID: UInt64, indexes: [Int]) async throws {
        try await queue.run { [self] in
            let app = try musicApp()
            let playlist = try playlistObject(id: playlistID, in: app)
            let tracks = try Self.elementArray(playlist, "tracks") ?? {
                throw MusicServiceError(code: .scriptFailed("tracks"), message: "Playlist returned no tracks element")
            }()
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
            let newCount = (Self.elementArray(playlist, "tracks") ?? tracks).count
            guard newCount == count - sorted.count else {
                throw MusicServiceError(code: .safetyCheckFailed,
                                        message: "Playlist changed during removal (\(count) → \(newCount), expected \(count - sorted.count))")
            }
        }
    }

    private func playlistObject(id: UInt64, in app: SBApplication) throws -> NSObject {
        guard let playlists = Self.elementArray(app, "playlists") else {
            throw MusicServiceError(code: .scriptFailed("playlists"), message: "Music returned no playlists element")
        }
        for index in 0..<playlists.count {
            if let playlist = playlists.object(at: index) as? NSObject,
               Self.int(playlist, "id") == Int(id) {
                return playlist
            }
        }
        throw MusicServiceError(code: .safetyCheckFailed, message: "Playlist not found")
    }

    private static func parsePersistentID(_ raw: String?) -> UInt64 {
        guard let raw, !raw.isEmpty else { return 0 }
        return UInt64(raw, radix: Constants.Track.persistentIDRadix)
            ?? UInt64(raw)
            ?? UInt64(abs(raw.hashValue))
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
