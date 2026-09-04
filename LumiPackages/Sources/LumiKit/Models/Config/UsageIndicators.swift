import Foundation

/// Topbar'daki sağlayıcı kullanım göstergelerinin açık/kapalı durumu
/// (`~/.lumi/config.json` → `usageIndicators`, karar 32). Kapalı sağlayıcı için
/// topbar'da buton çıkmaz ve HİÇBİR istek atılmaz — ne manuel ne otomatik.
/// Default claude açık (mevcut davranışın korunması), codex kapalı.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct UsageIndicators: Sendable, Equatable {
    public var claude: Bool
    public var codex: Bool

    public static let defaults = UsageIndicators(claude: true, codex: false)

    public init(claude: Bool, codex: Bool) {
        self.claude = claude
        self.codex = codex
    }

    public func isEnabled(_ provider: AgentProvider) -> Bool {
        switch provider {
        case .claude: return claude
        case .codex: return codex
        }
    }

    /// Immutable setter — mevcut değeri değiştirmez, yeni kopya döner.
    public func setting(_ enabled: Bool, for provider: AgentProvider) -> UsageIndicators {
        switch provider {
        case .claude: return UsageIndicators(claude: enabled, codex: codex)
        case .codex: return UsageIndicators(claude: claude, codex: enabled)
        }
    }

    /// Topbar'ın çizeceği göstergeler — `AgentProvider.allCases` sırasında.
    public var enabledProviders: [AgentProvider] {
        AgentProvider.allCases.filter(isEnabled)
    }
}

/// Kullanım göstergesinin otomatik tazelenmesi (`~/.lumi/config.json` →
/// `usageAutoRefresh`). Opt-in (karar 20): kapalıyken hiçbir otomatik istek
/// atılmaz. Açıkken `intervalMinutes`'te bir, YALNIZCA kullanıcı aktifse (son
/// HID girdisinden bu yana aralıktan az süre geçmişse) tazelenir; Mac uykudayken
/// process askıda olduğundan tetiklenmez.
///
/// **Persistence yalnız `ConfigCodec` üzerinden — karar 9.**
public struct UsageAutoRefresh: Sendable, Equatable {
    public var enabled: Bool
    /// Tazeleme aralığı (dakika). Yalnız `allowedIntervals` değerleri geçerli;
    /// dışındaki değerler default'a düşer.
    public var intervalMinutes: Int

    /// UI'da sunulan ve kabul edilen aralık seçenekleri (K38 kararı A,
    /// design/05 §6.1). En küçük aralık, servis katmanındaki TTL cache'iyle
    /// (`CachingUsageService`, ≥5 dk) hizalıdır: daha sık bir aralık cache'e
    /// takılıp gerçek bir tazeleme üretmezdi.
    public static let allowedIntervals = [5, 15, 30]

    public static let defaults = UsageAutoRefresh(enabled: false, intervalMinutes: 5)

    /// Doğrulama sözleşmesi: izinli set dışındaki her değer (eski dosyalardaki
    /// `1` dahil) default'a clamp'lenir. Karar 9 ihlali DEĞİLDİR — bu tip zaten
    /// baştan beri doğrulayan bir init'e sahipti; yalnız izinli set daraldı.
    public init(enabled: Bool, intervalMinutes: Int) {
        self.enabled = enabled
        self.intervalMinutes = Self.allowedIntervals.contains(intervalMinutes)
            ? intervalMinutes
            : Self.defaults.intervalMinutes
    }
}
