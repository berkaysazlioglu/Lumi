import Foundation
import LumiKit
import SwiftUI

/// Kullanım limitlerinin UI metinleri (refactor 5.9): model katmanı sunum
/// string'i taşımaz — `UsageLimit` yalnız kind + ham etiketi bilir.
extension UsageLimit {
    /// Tanınan türler normalize edilir, tanınmayan ham etiketi kullanır.
    var displayTitle: String {
        switch kind {
        case .session: return "5-hour session"
        case .weeklyAll: return "Weekly (all models)"
        case .weeklyModel(let name): return "Weekly (\(name))"
        case .other: return rawLabel
        }
    }
}

/// Uyarı seviyesi → renk (refactor 7.5): eşik mantığı LumiKit'te
/// (`UsageLevel`), tema eşlemesi burada. Model katmanı renk bilmez.
extension UsageLevel {
    var color: Color {
        switch self {
        case .normal: return Theme.success
        case .warning: return Theme.warning
        case .critical: return Theme.error
        }
    }
}
