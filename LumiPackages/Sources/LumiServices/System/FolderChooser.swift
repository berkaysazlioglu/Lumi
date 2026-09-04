import AppKit
import Foundation

/// `dialog:open-folder` karşılığı: NSOpenPanel (yalnız dizin, tekli seçim).
/// Tip nonisolated; yalnız panel açan metod `@MainActor`dır.
public struct FolderChooser: Sendable {
    public init() {}

    @MainActor
    public func choose() async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
