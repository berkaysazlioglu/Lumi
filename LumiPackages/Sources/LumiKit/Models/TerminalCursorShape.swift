import Foundation

/// Terminal caret şekli (Settings → Terminal → Cursor).
/// `rawValue` config.json'da `terminalCursorStyle` anahtarında saklanır;
/// SwiftTerm `CursorStyle`'a çeviri LumiTerminal'de yapılır (SwiftTerm import'u orada).
public enum TerminalCursorShape: String, Codable, Sendable, CaseIterable, Identifiable {
    case block
    case underline
    case bar

    public var id: String { rawValue }

    /// Geçersiz/bilinmeyen string → `.block` (additive alan güvenliği, karar 9).
    public static func parse(_ raw: String) -> TerminalCursorShape {
        TerminalCursorShape(rawValue: raw) ?? .block
    }
}
