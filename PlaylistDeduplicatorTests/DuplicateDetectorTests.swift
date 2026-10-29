import XCTest
@testable import PlaylistDeduplicator

final class DuplicateDetectorTests: XCTestCase {
    private func entry(_ index: Int, track: Track, playlistID: UInt64 = 1) -> PlaylistEntry {
        PlaylistEntry(playlistID: playlistID, index: index, track: track)
    }

    private func track(id: UInt64, title: String, artist: String = "A", album: String = "B",
                       duration: Double = 200) -> Track {
        Track(persistentID: id, title: title, artist: artist, album: album, duration: duration, location: nil)
    }

    func testNoDuplicates() {
        let entries = [
            entry(1, track: track(id: 1, title: "X")),
            entry(2, track: track(id: 2, title: "Y"))
        ]
        XCTAssertTrue(DuplicateDetector().duplicateGroups(in: entries).isEmpty)
    }

    func testSamePersistentIDDuplicate() {
        let t = track(id: 42, title: "X")
        let groups = DuplicateDetector().duplicateGroups(in: [
            entry(1, track: t), entry(2, track: track(id: 9, title: "Z")), entry(3, track: t)
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].keep.index, 1)
        XCTAssertEqual(groups[0].removals.map(\.index), [3])
    }

    func testMetadataMatchWithinDurationTolerance() {
        let groups = DuplicateDetector().duplicateGroups(in: [
            entry(1, track: track(id: 1, title: "Song", duration: 200)),
            entry(2, track: track(id: 2, title: "Song", duration: 201.5))
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].removals.map(\.index), [2])
    }

    func testLiveVsStudioNotDuplicates() {
        // Same title/artist/album but durations differ by 60 s.
        let groups = DuplicateDetector().duplicateGroups(in: [
            entry(1, track: track(id: 1, title: "Song", duration: 200)),
            entry(2, track: track(id: 2, title: "Song", duration: 260))
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testSameTitleDifferentVersionsDifferentAlbums() {
        let groups = DuplicateDetector().duplicateGroups(in: [
            entry(1, track: track(id: 1, title: "Song", album: "Studio")),
            entry(2, track: track(id: 2, title: "Song", album: "Live"))
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testTripleOccurrenceKeepsFirst() {
        let t = track(id: 7, title: "Song")
        let groups = DuplicateDetector().duplicateGroups(in: [
            entry(1, track: t), entry(2, track: t), entry(3, track: t)
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].removals.count, 2)
        XCTAssertEqual(groups[0].removals.map(\.index), [2, 3])
    }

    func testMissingMetadataNotMatchedAgainstEachOther() {
        // Two untitled tracks with different IDs and no album: must not
        // be treated as duplicates purely for missing metadata.
        let groups = DuplicateDetector().duplicateGroups(in: [
            entry(1, track: track(id: 1, title: "", album: "")),
            entry(2, track: track(id: 2, title: "", album: ""))
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testCaseAndWhitespaceInsensitive() {
        let groups = DuplicateDetector().duplicateGroups(in: [
            entry(1, track: track(id: 1, title: "  Song ", duration: 200)),
            entry(2, track: track(id: 2, title: "sONG", duration: 200))
        ])
        XCTAssertEqual(groups.count, 1)
    }

    func testConfigurableTolerance() {
        var config = DuplicateDetector.Configuration.default
        config.durationToleranceSeconds = 10
        let groups = DuplicateDetector(configuration: config).duplicateGroups(in: [
            entry(1, track: track(id: 1, title: "Song", duration: 200)),
            entry(2, track: track(id: 2, title: "Song", duration: 209))
        ])
        XCTAssertEqual(groups.count, 1)
    }

    func testPersistentIDPriorityOverMetadata() {
        // Same metadata as the ID group's kept entry but different ID:
        // must not create a second overlapping group.
        let groups = DuplicateDetector().duplicateGroups(in: [
            entry(1, track: track(id: 1, title: "Song", duration: 200)),
            entry(2, track: track(id: 1, title: "Song", duration: 200)),
            entry(3, track: track(id: 2, title: "Song", duration: 200))
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].entries.count, 3)
    }
}
