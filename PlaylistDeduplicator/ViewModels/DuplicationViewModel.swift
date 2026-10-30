import Foundation
import Observation

/// Owns the duplicate groups for the selected playlist and the
/// per-group removal selection.
@MainActor @Observable
final class DuplicationViewModel {
    private(set) var groups: [DuplicateGroup] = []
    /// Entry IDs currently selected for removal (default: all but the kept one).
    private(set) var selectedForRemoval: Set<String> = []
    private(set) var isLoading = false
    private(set) var isRemoving = false
    var errorMessage: String?

    private let service: MusicLibraryService
    private let detector: DuplicateDetector
    private var currentPlaylist: Playlist?

    init(service: MusicLibraryService, config: AppConfig = ConfigStore.load()) {
        self.service = service
        self.detector = DuplicateDetector(configuration: .init(
            durationToleranceSeconds: config.duplicateDetection.durationToleranceSeconds,
            matchByPersistentIDFirst: config.duplicateDetection.matchByPersistentIDFirst,
            caseInsensitiveTextMatch: config.duplicateDetection.caseInsensitiveTextMatch
        ))
    }

    var selectedEntries: [PlaylistEntry] {
        groups.flatMap(\.entries).filter { selectedForRemoval.contains($0.id) }
            .sorted { $0.index < $1.index }
    }

    var selectedCount: Int { selectedEntries.count }

    func load(playlist: Playlist) async {
        isLoading = true
        errorMessage = nil
        groups = []
        selectedForRemoval = []
        currentPlaylist = playlist
        defer { isLoading = false }
        do {
            // Timeout-bounded fetch: one unresponsive playlist must not
            // hang the UI.
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
            guard let fetched = entries else {
                errorMessage = "Playlist did not respond within 20 s — try again."
                return
            }
            groups = detector.duplicateGroups(in: fetched)
            selectedForRemoval = Set(groups.flatMap(\.removals).map(\.id))
        } catch let error as MusicServiceError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ entry: PlaylistEntry) {
        if selectedForRemoval.contains(entry.id) {
            selectedForRemoval.remove(entry.id)
        } else {
            selectedForRemoval.insert(entry.id)
        }
    }

    func selectAllRemovals(in group: DuplicateGroup) {
        group.removals.forEach { selectedForRemoval.insert($0.id) }
    }

    func clearRemovals(in group: DuplicateGroup) {
        group.removals.forEach { selectedForRemoval.remove($0.id) }
    }

    /// Removes the selected entries from the selected playlist only.
    func removeSelected() async {
        guard let playlist = currentPlaylist, !selectedEntries.isEmpty else { return }
        isRemoving = true
        errorMessage = nil
        defer { isRemoving = false }
        do {
            try await service.removeEntries(
                playlistID: playlist.id,
                indexes: selectedEntries.map(\.index)
            )
            await load(playlist: playlist)
        } catch let error as MusicServiceError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
