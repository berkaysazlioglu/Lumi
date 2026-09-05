import Foundation

/// Kullanım yüzdesinin uyarı seviyesi (refactor 7.5).
///
/// Eşik mantığı SAF ve view'sızdır; renk eşlemesi LumiUI'daki presenter'ın işi
/// (`UsageLevel.color`). Böylece "yeşil < %50 ≤ sarı < %80 ≤ kırmızı" kuralı
/// tema değişse de tek yerde kalır ve birim testten görünür.
public enum UsageLevel: Sendable, Equatable, CaseIterable {
    case normal
    case warning
    case critical

    /// Uyarı eşiği (dahil) — bu değerden itibaren `.warning`.
    public static let warningThreshold = 50
    /// Kritik eşiği (dahil) — bu değerden itibaren `.critical`.
    public static let criticalThreshold = 80

    /// Aralık dışı değerler (bozuk CLI verisi) en yakın banda düşer.
    public init(percent: Int) {
        switch percent {
        case ..<Self.warningThreshold: self = .normal
        case ..<Self.criticalThreshold: self = .warning
        default: self = .critical
        }
    }
}
