import Foundation

/// Terminal caret şekli (Settings → Terminal → Cursor).
/// `rawValue` config.json'da `terminalCursorStyle` anahtarında saklanır;
/// SwiftTerm `CursorStyle`'a çeviri LumiTerminal'de yapılır (SwiftTerm import'u orada).
public enum TerminalCursorShape: String, Codable, Sendable, CaseIterable, Identifiable {
    case block
    case underline
    case bar

    public var id: String { rawValue }

    /// UI etiketleri (segmented seçim).
    public var label: String {
        switch self {
        case .block: return "Block"
        case .underline: return "Underline"
        case .bar: return "Bar"
        }
    }

    /// Geçersiz/bilinmeyen string → `.block` (additive alan güvenliği, karar 9).
    public static func parse(_ raw: String) -> TerminalCursorShape {
        TerminalCursorShape(rawValue: raw) ?? .block
    }
}
