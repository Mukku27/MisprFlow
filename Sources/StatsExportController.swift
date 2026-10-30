import AppKit
import Foundation
import UniformTypeIdentifiers

/// Presents the stats CSV save panel and writes the export. Kept out of
/// AppState so the model layer stays free of AppKit panel code.
enum StatsExportController {
    /// Presents a NSSavePanel and writes the CSV to the chosen location.
    /// Must be called on the main thread.
    @MainActor
    static func exportWithSavePanel(csv: String, fileName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = fileName
        panel.title = "Export Stats"
        panel.message = "Daily totals only. No transcripts are included."
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try csv.write(to: destination, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}
