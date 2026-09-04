import Foundation
import LumiKit

/// Git modellerinin UI metinleri (refactor 5.9).
extension FileChangeStatus {
    /// Changes panelindeki / commit dosya listesindeki tek harfli rozet.
    var badgeText: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "U"
        }
    }
}
