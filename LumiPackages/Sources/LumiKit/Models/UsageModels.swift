import Foundation

/// Tek bir kullanım penceresi (5 saatlik oturum / haftalık limitler).
/// Alanlar opsiyonel — parse kısmen başarısız olsa bile veri düşmez
/// (design/05 §5: parse hatası veriyi düşürmez).
public struct UsageWindow: Sendable, Equatable {
    /// 0–100; parse edilemezse nil.
    public let percentUsed: Int?
    /// Reset zamanı `Date`'e çevrilebildiyse (içinde bulunulan yıl varsayımı).
    public let resetsAt: Date?
    /// Ham reset metni (örn. `Jun 12 at 1:39pm`); parse başarısız olsa da saklanır.
    public let resetsRaw: String
    /// Parantez içi timezone (örn. `Europe/Istanbul`), varsa.
    public let timezone: String?

    public init(percentUsed: Int?, resetsAt: Date?, resetsRaw: String, timezone: String?) {
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.resetsRaw = resetsRaw
        self.timezone = timezone
    }
}

/// `claude -p "/usage"` çıktısının yapısal hali (design/05 §5). Immutable.
public struct UsageSnapshot: Sendable, Equatable {
    public enum Mode: String, Sendable {
        case subscription
        case apiKey
        case unknown
    }

    public let fiveHour: UsageWindow?      // en önemli alan (topbar göstergesi)
    public let weekAll: UsageWindow?
    public let weekSonnet: UsageWindow?
    public let weekOpus: UsageWindow?
    public let mode: Mode
    public let fetchedAt: Date

    public init(
        fiveHour: UsageWindow?,
        weekAll: UsageWindow?,
        weekSonnet: UsageWindow?,
        weekOpus: UsageWindow?,
        mode: Mode,
        fetchedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.weekAll = weekAll
        self.weekSonnet = weekSonnet
        self.weekOpus = weekOpus
        self.mode = mode
        self.fetchedAt = fetchedAt
    }

    /// En az bir pencere parse edilebildi mi? (mode `.unknown` + tüm pencereler
    /// nil → servis "biçim tanınmadı" hatası verir, design/05 §hata yönetimi.)
    public var hasAnyWindow: Bool {
        fiveHour != nil || weekAll != nil || weekSonnet != nil || weekOpus != nil
    }
}
