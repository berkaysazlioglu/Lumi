import Foundation
import LumiKit

/// Terminal/provider modellerinin UI metinleri (refactor 5.9).
extension TerminalCursorShape {
    /// Settings → Terminal → Cursor segmented seçiminin etiketi.
    var displayLabel: String {
        switch self {
        case .block: return "Block"
        case .underline: return "Underline"
        case .bar: return "Bar"
        }
    }
}

extension AgentProvider {
    /// Buton etiketi ("New Claude" / "New Codex"), usage başlıkları.
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}
