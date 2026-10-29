import XCTest
@testable import PlaylistDeduplicator

final class ConfigStoreTests: XCTestCase {
    func testDefaultsWhenNoJSON() {
        XCTAssertNil(ConfigStore.load(from: Data("not json".utf8)))
    }

    func testOverridesApplied() {
        let json = """
        {
          "duplicateDetection": { "durationToleranceSeconds": 5.5 },
          "playlists": { "excludedNames": ["Custom"] },
          "aiAssist": { "enabled": false, "model": "mymodel" },
          "export": { "defaultFormat": "markdown" }
        }
        """
        let config = ConfigStore.load(from: Data(json.utf8))
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.duplicateDetection.durationToleranceSeconds, 5.5)
        XCTAssertEqual(config?.playlists.excludedNames, ["Custom"])
        XCTAssertEqual(config?.aiAssist.enabled, false)
        XCTAssertEqual(config?.aiAssist.model, "mymodel")
        XCTAssertEqual(config?.export.defaultFormat, "markdown")
        // Unspecified nested values keep defaults.
        XCTAssertEqual(config?.aiAssist.keychainService, Constants.AIAssist.keychainService)
    }

    func testBundledConfigParses() {
        let url = Bundle(for: type(of: self)).url(forResource: "config", withExtension: "json")
        if let url, let data = try? Data(contentsOf: url) {
            XCTAssertNotNil(ConfigStore.load(from: data))
        }
    }
}

final class ReportExporterTests: XCTestCase {
    private func sampleGroups() -> [DuplicateGroup] {
        let track = Track(persistentID: 9, title: "Song", artist: "Art,ist", album: "Alb", duration: 200, location: nil)
        return [
            DuplicateGroup(
                keep: PlaylistEntry(playlistID: 1, index: 1, track: track),
                removals: [PlaylistEntry(playlistID: 1, index: 4, track: track)]
            )
        ]
    }

    func testCSVEscapesQuotesAndCommas() {
        let csv = ReportExporter().report(for: sampleGroups(), playlistName: "P", format: .csv)
        XCTAssertTrue(csv.contains("\"Art,ist\""))
        XCTAssertTrue(csv.contains("Song"))
    }

    func testMarkdownContainsHeadings() {
        let md = ReportExporter().report(for: sampleGroups(), playlistName: "P", format: .markdown)
        XCTAssertTrue(md.contains("# Duplicate Report — P"))
        XCTAssertTrue(md.contains("## Group 1"))
        XCTAssertTrue(md.contains("| 1 | ✓ |"))
    }

    func testCSVHeaderMatchesConfiguredColumns() {
        let csv = ReportExporter(columns: ["group", "title"]).report(for: [], playlistName: "P", format: .csv)
        XCTAssertEqual(csv.trimmingCharacters(in: .whitespacesAndNewlines), "group,title")
    }
}

final class KeychainStoreTests: XCTestCase {
    func testMissingKeyReturnsNil() {
        let store = KeychainStore(service: "com.example.PlaylistDeduplicator.tests.missing",
                                  account: "no-such-account")
        XCTAssertNil(store.readAPIKey())
    }
}
