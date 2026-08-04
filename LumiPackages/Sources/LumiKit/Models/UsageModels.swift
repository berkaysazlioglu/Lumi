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

/// `/usage` çıktısındaki TEK bir limit satırı: türü + ham etiketi + penceresi.
///
/// Model listesi CLI tarafında değişkendir (Sonnet/Opus/Fable satırları gelir,
/// gider). Bu yüzden snapshot sabit alanlar yerine bu tipten oluşan bir LİSTE
/// tutar: 3 yerine 2 (ya da 5) limit dönmesi hata değil, normal durumdur.
public struct UsageLimit: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// 5 saatlik oturum limiti (topbar göstergesinin kaynağı).
        case session
        /// Haftalık toplam ("all models").
        case weeklyAll
        /// Haftalık model-özel limit; ad CLI çıktısından gelir ("Opus", "Fable"…).
        case weeklyModel(String)
        /// Tanınmayan ama limit biçiminde (`N% used`) gelen satır — düşürülmez.
        case other
    }

    public let kind: Kind
    /// `:` öncesindeki ham etiket (örn. `Current week (Fable)`).
    public let rawLabel: String
    public let window: UsageWindow

    public init(kind: Kind, rawLabel: String, window: UsageWindow) {
        self.kind = kind
        self.rawLabel = rawLabel
        self.window = window
    }

    /// Aynı limitin iki kez gelmesini ayırt etmek için stabil anahtar.
    public var id: String {
        switch kind {
        case .session: return "session"
        case .weeklyAll: return "week.all"
        case .weeklyModel(let name): return "week.\(name.lowercased())"
        case .other: return "other.\(rawLabel.lowercased())"
        }
    }

    /// UI başlığı — tanınan türler normalize edilir, tanınmayan ham etiketi kullanır.
    public var title: String {
        switch kind {
        case .session: return "5-hour session"
        case .weeklyAll: return "Weekly (all models)"
        case .weeklyModel(let name): return "Weekly (\(name))"
        case .other: return rawLabel
        }
    }
}

/// `claude -p "/usage"` çıktısının yapısal hali (design/05 §5). Immutable.
///
/// `limits` CLI'ın yazdığı SIRAYI korur; UI bu listeyi olduğu gibi gezer →
/// yeni bir model limiti eklendiğinde ya da kaldırıldığında kod değişmez.
public struct UsageSnapshot: Sendable, Equatable {
    public enum Mode: String, Sendable {
        case subscription
        case apiKey
        case unknown
    }

    public let limits: [UsageLimit]
    public let mode: Mode
    public let fetchedAt: Date

    public init(limits: [UsageLimit], mode: Mode, fetchedAt: Date) {
        self.limits = limits
        self.mode = mode
        self.fetchedAt = fetchedAt
    }

    /// En önemli alan (topbar göstergesi): 5 saatlik oturum.
    public var fiveHour: UsageWindow? { window(ofKind: .session) }

    /// Haftalık toplam.
    public var weekAll: UsageWindow? { window(ofKind: .weeklyAll) }

    /// Haftalık model-özel limit (ad karşılaştırması case-insensitive).
    public func weekly(model: String) -> UsageWindow? {
        limits.first {
            if case .weeklyModel(let name) = $0.kind {
                return name.caseInsensitiveCompare(model) == .orderedSame
            }
            return false
        }?.window
    }

    public func window(ofKind kind: UsageLimit.Kind) -> UsageWindow? {
        limits.first { $0.kind == kind }?.window
    }

    /// En az bir pencere parse edilebildi mi? (mode `.unknown` + hiç limit yok
    /// → servis "biçim tanınmadı" hatası verir, design/05 §hata yönetimi.)
    public var hasAnyWindow: Bool { !limits.isEmpty }
}
