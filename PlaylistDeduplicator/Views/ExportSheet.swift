import AppKit
import SwiftUI

/// Sheet that exports a duplicate report (CSV/Markdown) to a
/// user-chosen location.
struct ExportSheet: View {
    @Environment(DuplicationViewModel.self) private var duplication
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist

    @State private var format: ReportExporter.Format = .csv
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Duplicate Report").font(.headline)
            Picker("Format", selection: $format) {
                Text("CSV").tag(ReportExporter.Format.csv)
                Text("Markdown").tag(ReportExporter.Format.markdown)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Text("\(duplication.groups.count) groups for “\(playlist.name)”")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Choose Location…") { export() }
                    .keyboardShortcut(.defaultAction)
            }
            if let exportError {
                Text(exportError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func export() {
        let exporter = ReportExporter()
        let report = exporter.report(for: duplication.groups, playlistName: playlist.name, format: format)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.commaSeparatedText, .plainText]
        savePanel.nameFieldStringValue = "duplicates-\(playlist.name.replacingOccurrences(of: "/", with: "-")).\(format.rawValue)"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try exporter.write(report: report, to: url)
                DispatchQueue.main.async { dismiss() }
            } catch {
                DispatchQueue.main.async {
                    exportError = error.localizedDescription
                }
            }
        }
    }
}
