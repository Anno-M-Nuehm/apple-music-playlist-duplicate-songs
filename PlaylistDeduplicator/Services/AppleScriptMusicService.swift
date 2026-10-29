import AppKit
import Foundation

/// Real Music integration via NSAppleScript.
///
/// Security: every script uses positional parameters (`on run {a, b}`),
/// so no library data (playlist names, track titles, paths) is ever
/// interpolated into AppleScript source text — this eliminates the
/// AppleScript injection class entirely. Only `playlistID` and integer
/// indexes (UInt64/Int, validated numeric types) are passed as
/// parameters, and every operation references exactly one playlist.
final class AppleScriptMusicService: MusicLibraryService, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.example.PlaylistDeduplicator.applescript")
    private(set) var lastError: MusicServiceError?

    private static let fetchPlaylistsScript = """
        on run {}
            tell application "Music"
                set output to ""
                repeat with p in (every user playlist)
                    set output to output & (id of p as text) & "\\u0001" & (name of p) & "\\u0001" & (count of tracks of p as text) & "\\u0001" & ((smart of p) as text) & "\\u0002"
                end repeat
                return output
            end tell
        end run
        """

    private static let fetchEntriesScript = """
        on run {playlistID}
            tell application "Music"
                set target to first user playlist whose id is playlistID
                set output to ""
                repeat with t in (every track of target)
                    set output to output & (id of t as text) & "\\u0001" & (name of t) & "\\u0001" & (artist of t) & "\\u0001" & (album of t) & "\\u0001" & ((duration of t) as text) & "\\u0001" & (location of t as text) & "\\u0002"
                end repeat
                return output
            end tell
        end run
        """

    /// Deletes tracks at 1-based indexes in one playlist, using Music's
    /// own `repeat/delete` with descending indexes so each deletion
    /// does not shift the remaining target indexes. A count check
    /// before and after guards against concurrent library changes.
    private static let removeEntriesScript = """
        on run {playlistID, indexList, expectedCount}
            tell application "Music"
                set target to first user playlist whose id is playlistID
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

    func fetchPlaylists() async throws -> [Playlist] {
        try await queue.run { [self] in
            let output = try execute(script: Self.fetchPlaylistsScript, parameters: [])
            return output
                .split(separator: "\u{0002}", omittingEmptySubsequences: true)
                .compactMap(Self.parsePlaylist)
        }
    }

    func fetchEntries(playlistID: UInt64) async throws -> [PlaylistEntry] {
        try await queue.run { [self] in
            let output = try execute(script: Self.fetchEntriesScript, parameters: [playlistID])
            return output
                .split(separator: "\u{0002}", omittingEmptySubsequences: true)
                .enumerated()
                .compactMap { Self.parseEntry($0.element, playlistID: playlistID, index: $0.offset + 1) }
        }
    }

    func removeEntries(playlistID: UInt64, indexes: [Int]) async throws {
        try await queue.run { [self] in
            let entries = try self.executeFetchEntries(playlistID: playlistID)
            let sorted = Set(indexes).sorted(by: >)
            guard !entries.isEmpty,
                  !sorted.isEmpty,
                  sorted.allSatisfy({ (1...entries.count).contains($0) }) else {
                throw MusicServiceError(code: .safetyCheckFailed, message: "Index out of range")
            }
            let parameters: [Any] = [playlistID, sorted, entries.count]
            let result = try execute(script: Self.removeEntriesScript, parameters: parameters)
            guard result == "OK" else {
                throw MusicServiceError(code: .safetyCheckFailed, message: "Playlist changed during removal")
            }
        }
    }

    private func executeFetchEntries(playlistID: UInt64) throws -> [PlaylistEntry] {
        let output = try execute(script: Self.fetchEntriesScript, parameters: [playlistID])
        return output
            .split(separator: "\u{0002}", omittingEmptySubsequences: true)
            .enumerated()
            .compactMap { Self.parseEntry($0.element, playlistID: playlistID, index: $0.offset + 1) }
    }

    private func execute(script source: String, parameters: [Any]) throws -> String {
        guard let appleScript = NSAppleScript(source: source) else {
            throw MusicServiceError(code: .scriptFailed("init"), message: "Could not compile script")
        }
        let parametersDescriptor = NSAppleEventDescriptor.list()
        for parameter in parameters.reversed() {
            parametersDescriptor.insert(Self.descriptor(for: parameter), at: 0)
        }
        if let event = appleScript.appleEvent {
            event.setDescriptor(parametersDescriptor, forKeyword: keyDirectObject)
        }
        var error: NSDictionary?
        let reply = appleScript.executeAndReturnError(&error)
        guard error == nil else { throw Self.error(for: error) }
        return reply.stringValue ?? ""
    }

    private static func descriptor(for value: Any) -> NSAppleEventDescriptor {
        switch value {
        case let int as Int: return NSAppleEventDescriptor(int32: Int32(clamping: int))
        case let double as Double: return NSAppleEventDescriptor(double: double)
        case let string as String: return NSAppleEventDescriptor(string: string)
        case let list as [Int]:
            let descriptor = NSAppleEventDescriptor.list()
            for item in list.reversed() { descriptor.insert(NSAppleEventDescriptor(int32: Int32(clamping: item)), at: 0) }
            return descriptor
        default:
            let string = String(describing: value)
            return NSAppleEventDescriptor(string: string)
        }
    }

    private static func parsePlaylist(_ record: Substring) -> Playlist? {
        let fields = record.split(separator: "\u{0001}", omittingEmptySubsequences: false)
        guard fields.count == 4, let id = UInt64(fields[0]) else { return nil }
        return Playlist(
            id: id,
            name: String(fields[1]),
            trackCount: Int(fields[2]) ?? 0,
            isSmart: fields[3] == "true"
        )
    }

    private static func parseEntry(_ record: Substring, playlistID: UInt64, index: Int) -> PlaylistEntry? {
        let fields = record.split(separator: "\u{0001}", omittingEmptySubsequences: false)
        guard fields.count == 6, let id = UInt64(fields[0]) else { return nil }
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
