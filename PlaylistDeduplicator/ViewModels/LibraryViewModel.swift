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
            // Progressive scan: update per playlist so the middle pane
            // populates incrementally instead of after a long block.
            // Playlists with fewer than 2 tracks cannot contain
            // duplicates and are skipped without an Apple event.
            var counts: [UInt64: Int] = [:]
            scannedPlaylistCount = 0
            scanTotal = playlists.count
            for playlist in playlists where playlist.trackCount > 1 {
                // Per-playlist timeout: a single unresponsive playlist
                // (e.g. very large or on slow storage) must not stall
                // the whole scan. Race the fetch against a timer task.
                let entries: [PlaylistEntry]? = await withTaskGroup(of: [PlaylistEntry]?.self) { group in
                    group.addTask { [service] in
                        try? await service.fetchEntries(playlistID: playlist.id)
                    }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                        return nil
                    }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first ?? nil
                }
                if let entries {
                    counts[playlist.id] = detector.duplicateGroups(in: entries).count
                }
                scannedPlaylistCount += 1
                duplicateCounts = counts
                // Yield so the main actor can service UI events between
                // playlists — keeps selection and panes responsive.
                await Task.yield()
            }
            duplicateCounts = counts
        } catch let error as MusicServiceError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
