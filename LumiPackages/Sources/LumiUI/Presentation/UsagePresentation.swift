import Foundation
import LumiKit

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
