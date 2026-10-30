import AppKit
import Foundation

/// Real Music integration via NSAppleScript.
///
/// Security: every script is a static source string whose `run` handler
/// takes positional parameters. Only typed, validated values (playlist
/// persistent-ID strings, integer indexes) are passed as Apple event
/// parameters — no library data is ever interpolated into script text,
/// eliminating AppleScript injection. Library data only flows back as the
/// script's return value, which is parsed, never executed.
///
/// Playlist targeting uses Music's persistent ID (a hex string), which is
/// exact and stable; Music's numeric `id` can overflow Int32 event
/// descriptors for large libraries.
final class AppleScriptMusicService: MusicLibraryService, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.example.PlaylistDeduplicator.applescript")
    private var activeLibraryPath: String?
    private(set) var lastError: MusicServiceError?

    private static let fetchPlaylistsScript = """
        on run {}
            set fieldSep to ASCII character 1
            set recordSep to ASCII character 2
            tell application "Music"
                set output to ""
                repeat with p in (every user playlist)
                    set output to output & (persistent ID of p) & fieldSep & (name of p) & fieldSep & (count of tracks of p as text) & fieldSep & ((smart of p) as text) & recordSep
                end repeat
                return output
            end tell
        end run
        """

    private static let fetchEntriesScript = """
        on run {playlistPersistentID}
            set fieldSep to ASCII character 1
            set recordSep to ASCII character 2
            tell application "Music"
                set target to first user playlist whose persistent ID is playlistPersistentID
                set output to ""
                repeat with t in (every track of target)
                    set output to output & (persistent ID of t) & fieldSep & (name of t) & fieldSep & (artist of t) & fieldSep & (album of t) & fieldSep & ((duration of t) as text) & fieldSep & (location of t as text) & recordSep
                end repeat
                return output
            end tell
        end run
        """

    /// Deletes tracks at 1-based indexes in one playlist. Indexes are
    /// passed descending so each deletion does not shift the remaining
    /// target indexes. Count checks before and after guard against
    /// concurrent library changes; "MISMATCH" aborts with no changes.
    private static let removeEntriesScript = """
        on run {playlistPersistentID, indexList, expectedCount}
            tell application "Music"
                set target to first user playlist whose persistent ID is playlistPersistentID
                if (count of tracks of target) is not expectedCount then
                    return "MISMATCH"
                end if
                repeat with idx in indexList
                    delete track idx of target
                end repeat
                if (count of tracks of target) is not (expectedCount - (count of indexList)) then
                    return "MISMATCH"
                end if
                return "OK"
            end tell
        end run
        """

    func ensureAccess() async throws {
        try await queue.run { [self] in
            let appleScript = NSAppleScript(source: """
                on run {}
                    tell application "Music" to return name
                end run
                """)
            var error: NSDictionary?
            guard let descriptor = appleScript?.executeAndReturnError(&error),
                  descriptor.stringValue != nil else {
                throw Self.error(for: error)
            }
        }
    }

    private static let useLibraryScript = """
        on run {libraryPath}
            tell application "Music"
                open (POSIX file libraryPath)
                return name
            end tell
        end run
        """

    func useLibrary(at url: URL?) async throws {
        guard let url else { return }
        let path = url.path
        // Skip when the requested library is already active — reopening
        // the open library makes Music fail with an AppleScript error.
        if path == activeLibraryPath {
            try await ensureAccess()
            return
        }
        try await queue.run { [self] in
            _ = try execute(script: Self.useLibraryScript, handler: Constants.AppleEvents.scriptHandlerName,
                            parameters: [path])
        }
        // Music switches libraries asynchronously; wait until it responds
        // again before any scan touches the new library.
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
            let output = try execute(script: Self.fetchPlaylistsScript, handler: Constants.AppleEvents.scriptHandlerName, parameters: [])
            return output
                .split(separator: "\u{2}", omittingEmptySubsequences: true)
                .compactMap(Self.parsePlaylist)
        }
    }

    func fetchEntries(playlistID: UInt64) async throws -> [PlaylistEntry] {
        try await queue.run { [self] in
            try executeFetchEntries(playlistID: playlistID)
        }
    }

    func removeEntries(playlistID: UInt64, indexes: [Int]) async throws {
        try await queue.run { [self] in
            let entries = try executeFetchEntries(playlistID: playlistID)
            let sorted = Set(indexes).sorted(by: >)
            guard !entries.isEmpty,
                  !sorted.isEmpty,
                  sorted.allSatisfy({ (1...entries.count).contains($0) }) else {
                throw MusicServiceError(code: .safetyCheckFailed, message: "Index out of range")
            }
            let result = try execute(script: Self.removeEntriesScript, handler: Constants.AppleEvents.scriptHandlerName,
                                    parameters: [Self.persistentIDString(playlistID), sorted, entries.count])
            guard result == "OK" else {
                throw MusicServiceError(code: .safetyCheckFailed, message: "Playlist changed during removal")
            }
        }
    }

    private func executeFetchEntries(playlistID: UInt64) throws -> [PlaylistEntry] {
        let output = try execute(script: Self.fetchEntriesScript, handler: Constants.AppleEvents.scriptHandlerName,
                                 parameters: [Self.persistentIDString(playlistID)])
        return output
            .split(separator: "\u{2}", omittingEmptySubsequences: true)
            .enumerated()
            .compactMap { Self.parseEntry($0.element, playlistID: playlistID, index: $0.offset + 1) }
    }

    /// Compiles `source`, builds a subroutine Apple event (`«event aevtpsbr»`
    /// with handler name in `snam` and parameters as the direct object), and
    /// executes it with the compiled script's context.
    private func execute(script source: String, handler: String, parameters: [Any]) throws -> String {
        var compileError: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw MusicServiceError(code: .scriptFailed("init"), message: "Could not create script")
        }
        _ = appleScript.compileAndReturnError(&compileError)
        guard compileError == nil else { throw Self.error(for: compileError) }

        let target = NSAppleEventDescriptor(bundleIdentifier: Constants.App.musicAppBundleID)
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: Constants.AppleEvents.coreSuiteCode,
            eventID: Constants.AppleEvents.subroutineEventCode,
            targetDescriptor: target,
            returnID: Constants.AppleEvents.autoGenerateReturnID,
            transactionID: Constants.AppleEvents.anyTransactionID
        )
        event.setDescriptor(NSAppleEventDescriptor(string: handler), forKeyword: Constants.AppleEvents.subroutineNameCode)

        let arguments = NSAppleEventDescriptor.list()
        for parameter in parameters.reversed() {
            arguments.insert(Self.descriptor(for: parameter), at: 1)
        }
        event.setDescriptor(arguments, forKeyword: Constants.AppleEvents.directObjectCode)

        var executionError: NSDictionary?
        let reply = appleScript.executeAppleEvent(event, error: &executionError)
        guard executionError == nil else { throw Self.error(for: executionError) }
        return reply.stringValue ?? ""
    }

    /// Music persistent IDs are hex strings; keeping them as strings avoids
    /// any numeric conversion loss and keeps them out of script text.
    private static func persistentIDString(_ id: UInt64) -> String {
        String(id, radix: Constants.AppleEvents.persistentIDRadix, uppercase: true)
    }

    private static func descriptor(for value: Any) -> NSAppleEventDescriptor {
        switch value {
        case let int as Int:
            return NSAppleEventDescriptor(int32: Int32(clamping: int))
        case let double as Double:
            return NSAppleEventDescriptor(double: double)
        case let string as String:
            return NSAppleEventDescriptor(string: string)
        case let list as [Int]:
            let descriptor = NSAppleEventDescriptor.list()
            for item in list.reversed() {
                descriptor.insert(NSAppleEventDescriptor(int32: Int32(clamping: item)), at: 1)
            }
            return descriptor
        default:
            return NSAppleEventDescriptor(string: String(describing: value))
        }
    }

    private static func parsePlaylist(_ record: Substring) -> Playlist? {
        let fields = record.split(separator: "\u{1}", omittingEmptySubsequences: false)
        guard fields.count == 4, let id = UInt64(fields[0], radix: Constants.AppleEvents.persistentIDRadix) else { return nil }
        return Playlist(
            id: id,
            name: String(fields[1]),
            trackCount: Int(fields[2]) ?? 0,
            isSmart: fields[3] == "true"
        )
    }

    private static func parseEntry(_ record: Substring, playlistID: UInt64, index: Int) -> PlaylistEntry? {
        let fields = record.split(separator: "\u{1}", omittingEmptySubsequences: false)
        guard fields.count == 6, let id = UInt64(fields[0], radix: Constants.AppleEvents.persistentIDRadix) else { return nil }
        let location = fields[5].isEmpty ? nil : URL(fileURLWithPath: String(fields[5]))
        let track = Track(
            persistentID: id,
            title: String(fields[1]),
            artist: String(fields[2]),
            album: String(fields[3]),
            duration: Double(fields[4]) ?? 0,
            location: location
        )
        return PlaylistEntry(playlistID: playlistID, index: index, track: track)
    }

    private static func error(for error: NSDictionary?) -> MusicServiceError {
        guard let error, let number = error.value(forKey: NSAppleScript.errorNumber) as? Int else {
            return MusicServiceError(code: .scriptFailed("unknown"), message: "Unknown AppleScript error")
        }
        let message = (error.value(forKey: NSAppleScript.errorMessage) as? String) ?? "AppleScript error"
        if number == -1743 { return MusicServiceError(code: .notAuthorized, message: "Not authorized to send Apple Events to Music") }
        return MusicServiceError(code: .scriptFailed(String(number)), message: message)
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
