import Foundation
import Observation

/// Owns the playlists list and duplicate counts for the left two panes.
@MainActor @Observable
final class LibraryViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var duplicateCounts: [UInt64: Int] = [:]
    private(set) var isLoading = false
    private(set) var scannedPlaylistCount = 0
    private(set) var scanTotal = 0
    var errorMessage: String?

    /// The Music library to analyze; nil means the currently open one.
    /// Persisted across launches in UserDefaults.
    var selectedLibraryURL: URL? {
        didSet {
            if let selectedLibraryURL {
                UserDefaults.standard.set(selectedLibraryURL, forKey: Constants.Library.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Constants.Library.defaultsKey)
            }
        }
    }

    var selectedLibraryName: String? {
        selectedLibraryURL?.deletingPathExtension().lastPathComponent
    }

    /// Switches the analyzed library and rescans.
    func useLibrary(_ url: URL?) async {
        selectedLibraryURL = url
        await load()
    }

    private let service: MusicLibraryService
    private let config: AppConfig
    private let detector: DuplicateDetector

    init(service: MusicLibraryService, config: AppConfig = ConfigStore.load()) {
        self.service = service
        self.config = config
        self.selectedLibraryURL = UserDefaults.standard.url(forKey: Constants.Library.defaultsKey)
        self.detector = DuplicateDetector(configuration: .init(
            durationToleranceSeconds: config.duplicateDetection.durationToleranceSeconds,
            matchByPersistentIDFirst: config.duplicateDetection.matchByPersistentIDFirst,
            caseInsensitiveTextMatch: config.duplicateDetection.caseInsensitiveTextMatch
        ))
    }

    var playlistsWithDuplicates: [Playlist] {
        playlists.filter { (duplicateCounts[$0.id] ?? 0) > 0 }
    }

    /// Scans one playlist for duplicates and caches the count.
    /// Called when the user selects a playlist; bounded by a timeout so
    /// a single unresponsive playlist cannot hang the UI.
    func scan(playlist: Playlist) async {
        guard duplicateCounts[playlist.id] == nil, playlist.trackCount > 1 else { return }
        let entries: [PlaylistEntry]? = await withTaskGroup(of: [PlaylistEntry]?.self) { group in
            group.addTask { [service] in
                try? await service.fetchEntries(playlistID: playlist.id)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }
        if let entries {
            var counts = duplicateCounts
            counts[playlist.id] = detector.duplicateGroups(in: entries).count
            duplicateCounts = counts
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await service.ensureAccess()
            do {
                try await service.useLibrary(at: selectedLibraryURL)
            } catch {
                // Library switch failed (e.g. copy unreachable): fall
                // back to scanning the currently open library.
                errorMessage = "Could not switch library — using the currently open one.\n\(error.localizedDescription)"
            }
            // Special sources (Music, Movies, ...) are already filtered by
            // the service via specialKind; name-based exclusion is only a
            // secondary, localization-independent safety net.
            let fetched = try await service.fetchPlaylists()
            playlists = fetched.filter { playlist in
                if playlist.isSmart && !config.playlists.includeSmartPlaylists { return false }
                return !config.playlists.excludedNames.contains(playlist.name)
            }
            // Launch no longer pre-scans every playlist: that took
            // minutes on large libraries. Playlists are listed instantly;
            // duplicates for a playlist are computed when the user
            // selects it (see scan(playlist:)), and cached.
            duplicateCounts = [:]
        } catch let error as MusicServiceError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
