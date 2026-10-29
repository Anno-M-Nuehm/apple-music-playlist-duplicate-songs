import Foundation

/// Pure duplicate-detection logic, fully unit-testable.
///
/// Strategy (priority order):
/// 1. Same persistent track ID within a playlist ⇒ duplicate.
/// 2. Same normalized title + artist + album AND duration within
///    `durationToleranceSeconds` ⇒ duplicate.
/// Groups produced by the two strategies that share any entry are
/// merged into a single group; within each merged group the first
/// occurrence (lowest playlist index) is kept.
struct DuplicateDetector: Sendable {
    struct Configuration: Sendable {
        var durationToleranceSeconds: Double = Constants.DuplicateDetection.defaultDurationToleranceSeconds
        var matchByPersistentIDFirst = Constants.DuplicateDetection.matchByPersistentIDFirst
        var caseInsensitiveTextMatch = true

        static let `default` = Configuration()
    }

    let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    /// Detects duplicate groups within a single playlist.
    func duplicateGroups(in entries: [PlaylistEntry]) -> [DuplicateGroup] {
        var rawGroups: [[PlaylistEntry]] = []

        if configuration.matchByPersistentIDFirst {
            var byID: [UInt64: [PlaylistEntry]] = [:]
            for entry in entries {
                byID[entry.track.persistentID, default: []].append(entry)
            }
            rawGroups += byID.values.filter { $0.count > 1 }
        }

        rawGroups += metadataGroups(in: entries)

        let merged = Self.merge(rawGroups)
        return merged
            .map { occurrences in
                let sorted = occurrences.sorted { $0.index < $1.index }
                return DuplicateGroup(keep: sorted[0], removals: Array(sorted.dropFirst()))
            }
            .sorted { $0.keep.index < $1.keep.index }
    }

    /// All entries flagged for removal across groups.
    static func removalEntries(in groups: [DuplicateGroup]) -> [PlaylistEntry] {
        groups.flatMap(\.removals)
    }

    private func metadataGroups(in entries: [PlaylistEntry]) -> [[PlaylistEntry]] {
        let candidates = entries.filter { hasComparableMetadata($0.track) }
        var byKey: [String: [PlaylistEntry]] = [:]
        for entry in candidates {
            byKey[entry.track.metadataKey, default: []].append(entry)
        }
        var groups: [[PlaylistEntry]] = []
        for occurrences in byKey.values where occurrences.count > 1 {
            // Split by duration: entries whose durations differ by more
            // than the tolerance are different versions (live vs. studio)
            // and never duplicates of each other.
            groups += durationClusters(occurrences).filter { $0.count > 1 }
        }
        return groups
    }

    /// Greedy clustering: each entry joins the first cluster whose head is
    /// within `durationToleranceSeconds`; otherwise it starts a new cluster.
    private func durationClusters(_ entries: [PlaylistEntry]) -> [[PlaylistEntry]] {
        var clusters: [[PlaylistEntry]] = []
        for entry in entries {
            if let matchIndex = clusters.firstIndex(where: {
                abs($0[0].track.duration - entry.track.duration) <= configuration.durationToleranceSeconds
            }) {
                clusters[matchIndex].append(entry)
            } else {
                clusters.append([entry])
            }
        }
        return clusters
    }

    private func hasComparableMetadata(_ track: Track) -> Bool {
        !track.title.trimmedAndLowercased.isEmpty
    }

    /// Merges groups that share at least one entry (union-find on entry IDs).
    private static func merge(_ groups: [[PlaylistEntry]]) -> [[PlaylistEntry]] {
        var parent: [String: String] = [:]
        func find(_ x: String) -> String {
            if parent[x] == nil { parent[x] = x; return x }
            var root = x
            while parent[root] != root { root = parent[root]! }
            parent[x] = root
            return root
        }
        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        for group in groups {
            guard let first = group.first?.id else { continue }
            for entry in group.dropFirst() { union(first, entry.id) }
        }
        var merged: [String: [PlaylistEntry]] = [:]
        for group in groups {
            for entry in group {
                merged[find(entry.id), default: []].append(entry)
            }
        }
        return Array(merged.values)
    }
}
