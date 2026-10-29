import XCTest
@testable import PlaylistDeduplicator

/// Integration tests of the full scan → detect → select → remove flow
/// against the mocked Music layer.
@MainActor
final class MockMusicIntegrationTests: XCTestCase {
    private func makeLibrary() throws -> (LibraryViewModel, DuplicationViewModel, MockMusicService) {
        let playlistA = Playlist(id: 10, name: "A", trackCount: 4, isSmart: false)
        let playlistB = Playlist(id: 20, name: "B", trackCount: 2, isSmart: false)
        let song = Track(persistentID: 1, title: "Song", artist: "X", album: "Y", duration: 200, location: nil)
        let service = MockMusicService(
            playlists: [playlistA, playlistB],
            entries: [
                10: [
                    PlaylistEntry(playlistID: 10, index: 1, track: song),
                    PlaylistEntry(playlistID: 10, index: 2, track: Track(persistentID: 2, title: "Other", artist: "X", album: "Y", duration: 200, location: nil)),
                    PlaylistEntry(playlistID: 10, index: 3, track: song),
                    PlaylistEntry(playlistID: 10, index: 4, track: song)
                ],
                20: [
                    PlaylistEntry(playlistID: 20, index: 1, track: Track(persistentID: 5, title: "Solo", artist: "X", album: "Y", duration: 200, location: nil))
                ]
            ]
        )
        return (LibraryViewModel(service: service), DuplicationViewModel(service: service), service)
    }

    func testScanFindsOnlyPlaylistWithDuplicates() async throws {
        let (library, _, _) = try makeLibrary()
        await library.load()
        XCTAssertEqual(library.playlists.count, 2)
        XCTAssertEqual(library.playlistsWithDuplicates.map(\.name), ["A"])
        XCTAssertEqual(library.duplicateCounts[10], 1)
        XCTAssertEqual(library.duplicateCounts[20], 0)
    }

    func testGroupsPreselectAllButFirst() async throws {
        let (_, duplication, _) = try makeLibrary()
        await duplication.load(playlist: Playlist(id: 10, name: "A", trackCount: 4, isSmart: false))
        XCTAssertEqual(duplication.groups.count, 1)
        XCTAssertEqual(duplication.selectedEntries.map(\.index), [3, 4])
    }

    func testRemoveAffectsOnlySelectedPlaylist() async throws {
        let (library, duplication, service) = try makeLibrary()
        await library.load()
        await duplication.load(playlist: library.playlists[0])
        await duplication.removeSelected()

        XCTAssertEqual(service.removalLog.count, 1)
        XCTAssertEqual(service.removalLog[0].playlistID, 10)
        XCTAssertEqual(Set(service.removalLog[0].indexes), [3, 4])
        XCTAssertEqual(service.entries[10]?.count, 2)
        XCTAssertEqual(service.entries[20]?.count, 1, "Other playlist must be untouched")
        XCTAssertTrue(duplication.groups.isEmpty, "Rescan after removal must show no duplicates")
    }

    func testToggleAndClearSelection() async throws {
        let (_, duplication, _) = try makeLibrary()
        let playlist = Playlist(id: 10, name: "A", trackCount: 4, isSmart: false)
        await duplication.load(playlist: playlist)
        let removal = try XCTUnwrap(duplication.groups.first?.removals.first)
        duplication.toggle(removal)
        XCTAssertTrue(duplication.selectedEntries.isEmpty)
        duplication.selectAllRemovals(in: try XCTUnwrap(duplication.groups.first))
        XCTAssertEqual(duplication.selectedCount, 2)
        duplication.clearRemovals(in: try XCTUnwrap(duplication.groups.first))
        XCTAssertEqual(duplication.selectedCount, 0)
    }

    func testExcludedPlaylistNamesFiltered() async throws {
        let playlist = Playlist(id: 30, name: "Music", trackCount: 0, isSmart: false)
        let service = MockMusicService(playlists: [playlist], entries: [30: []])
        let library = LibraryViewModel(service: service)
        await library.load()
        XCTAssertTrue(library.playlists.isEmpty)
    }

    func testRemovalErrorSurfaces() async throws {
        let service = MockMusicService(playlists: [], entries: [:])
        service.removeError = MusicServiceError(code: .safetyCheckFailed, message: "changed")
        let duplication = DuplicationViewModel(service: service)
        await duplication.load(playlist: Playlist(id: 1, name: "A", trackCount: 0, isSmart: false))
        await duplication.removeSelected()
        XCTAssertNotNil(duplication.errorMessage)
    }
}
