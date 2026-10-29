import Foundation

/// Exports duplicate reports as CSV or Markdown to a user-chosen location.
struct ReportExporter: Sendable {
    enum Format: String, CaseIterable, Sendable {
        case csv, markdown
    }

    enum ExportError: Error, Equatable {
        case writeFailed(underlying: String)
    }

    let columns: [String]

    init(columns: [String] = Constants.Export.reportColumns) {
        self.columns = columns
    }

    func report(for groups: [DuplicateGroup], playlistName: String, format: Format) -> String {
        switch format {
        case .csv: csvReport(for: groups, playlistName: playlistName)
        case .markdown: markdownReport(for: groups, playlistName: playlistName)
        }
    }

    func write(report: String, to url: URL) throws {
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(underlying: error.localizedDescription)
        }
    }

    private func csvReport(for groups: [DuplicateGroup], playlistName: String) -> String {
        var lines: [String] = [csvRow(columns)]
        for (groupIndex, group) in groups.enumerated() {
            for entry in group.entries {
                let row = [
                    "\(groupIndex + 1)",
                    entry.track.title,
                    entry.track.artist,
                    entry.track.album,
                    String(format: "%.1f", entry.track.duration),
                    String(entry.track.persistentID),
                    "\(group.entries.count)",
                    group.removals.contains(where: { $0.id == entry.id }) ? "yes" : "no"
                ]
                lines.append(csvRow(row))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func csvRow(_ fields: [String]) -> String {
        fields.map { field in
            if field.contains(",") || field.contains("\"") || field.contains("\n") {
                return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return field
        }.joined(separator: ",")
    }

    private func markdownReport(for groups: [DuplicateGroup], playlistName: String) -> String {
        var md = "# Duplicate Report — \(playlistName)\n\n"
        let date = ISO8601DateFormatter().string(from: Date())
        md += "Generated: \(date)\n"
        md += "Duplicate groups: \(groups.count)\n\n"
        for (index, group) in groups.enumerated() {
            md += "## Group \(index + 1)\n\n"
            md += "| Position | Keep | Title | Artist | Album | Duration |\n"
            md += "|---|---|---|---|---|---|\n"
            for entry in group.entries {
                let keep = entry.id == group.keep.id ? "✓" : "remove"
                md += "| \(entry.index) | \(keep) | \(entry.track.title) | \(entry.track.artist) | \(entry.track.album) | \(String(format: "%.1f", entry.track.duration))s |\n"
            }
            md += "\n"
        }
        return md
    }
}
