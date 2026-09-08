import AppKit
import LumiKit
import UniformTypeIdentifiers

/// Agent History dışa/içe aktarım dosya seçicileri (karar 52).
/// Yalnız URL seçer; okuma/yazma `AgentSessionTransferring`de kalır.
@MainActor
enum AgentSessionFilePanels {
    static let fileExtension = "lumisession.json"
    static let maxSlugLength = 40

    /// `<id-prefix>-<slug>.lumisession.json` önerisiyle kaydetme paneli.
    static func chooseExportDestination(for entry: AgentHistoryEntry) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Agent Session"
        panel.nameFieldStringValue = suggestedFileName(for: entry)
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseImportSource() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Agent Session"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func suggestedFileName(for entry: AgentHistoryEntry) -> String {
        let prefix = String(entry.sessionID.prefix(8))
        let slug = entry.title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let short = String(slug.prefix(maxSlugLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return [prefix, short].filter { !$0.isEmpty }.joined(separator: "-") + "." + fileExtension
    }
}
