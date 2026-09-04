import Foundation
import LumiKit

/// `config.json` → `usageAutoRefresh` ↔ `UsageAutoRefresh` (karar 20, K38-A).
/// Aralık doğrulaması modelin init'indedir: izinli set dışındaki değer (eski
/// dosyalardaki `1` dahil) OKUMADA default'a clamp'lenir, ilk yazımda da
/// clamp'li hâliyle diske döner.
enum UsageAutoRefreshCodec {
    static func decode(_ dict: [String: Any]?) -> UsageAutoRefresh {
        let defaults = UsageAutoRefresh.defaults
        guard let dict else { return defaults }

        return UsageAutoRefresh(
            enabled: JSONValue.bool(dict["enabled"]) ?? defaults.enabled,
            intervalMinutes: JSONValue.int(dict["intervalMinutes"]) ?? defaults.intervalMinutes
        )
    }

    static func overlay(_ settings: UsageAutoRefresh) -> [String: Any] {
        [
            "enabled": settings.enabled,
            "intervalMinutes": settings.intervalMinutes,
        ]
    }
}

/// `config.json` → `usageIndicators` ↔ `UsageIndicators` (karar 32).
enum UsageIndicatorsCodec {
    static func decode(_ dict: [String: Any]?) -> UsageIndicators {
        let defaults = UsageIndicators.defaults
        guard let dict else { return defaults }

        return UsageIndicators(
            claude: JSONValue.bool(dict["claude"]) ?? defaults.claude,
            codex: JSONValue.bool(dict["codex"]) ?? defaults.codex
        )
    }

    static func overlay(_ indicators: UsageIndicators) -> [String: Any] {
        [
            "claude": indicators.claude,
            "codex": indicators.codex,
        ]
    }
}
