import Foundation
import Observation

/// Owns the playlists list and duplicate counts for the left two panes.
@MainActor @Observable
final class LibraryViewModel {
    private(set) var playlists: [Playlist] = []
    private(set) var duplicateCounts: [UInt64: Int] = [:]
    private(set) var isLoading = false
    var errorMessage: String?

    private let service: MusicLibraryService
    private let config: AppConfig
    private let detector: DuplicateDetector

    init(service: MusicLibraryService, config: AppConfig = ConfigStore.load()) {
        self.service = service
        self.config = config
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
            let fetched = try await service.fetchPlaylists()
            playlists = fetched.filter { playlist in
                if playlist.isSmart && !config.playlists.includeSmartPlaylists { return false }
                return !config.playlists.excludedNames.contains(playlist.name)
            }
            var counts: [UInt64: Int] = [:]
            for playlist in playlists {
                let entries = try await service.fetchEntries(playlistID: playlist.id)
                counts[playlist.id] = detector.duplicateGroups(in: entries).count
            }
            duplicateCounts = counts
        } catch let error as MusicServiceError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
