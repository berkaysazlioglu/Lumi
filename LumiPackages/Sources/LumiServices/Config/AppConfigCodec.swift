import Foundation
import LumiKit

/// `~/.lumi/config.json` kök nesnesi ↔ `AppConfig`.
/// İç içe bölümler kendi codec'lerine devredilir; bu dosya yalnız kök alanları
/// ve bölüm bağlantılarını tutar.
enum AppConfigCodec {
    static func decode(_ dict: [String: Any]?) -> AppConfig {
        var config = AppConfig.defaults
        guard let dict else { return config }

        if let value = dict["projectsRoot"] as? String {
            config.projectsRoot = value
        }
        config.additionalPaths = AdditionalPathCodec.decodeList(dict["additionalPaths"])
        if let raw = dict["aiProvider"] as? String,
           let provider = AgentProvider(rawValue: raw) {
            config.aiProvider = provider
        }
        if let value = dict["theme"] as? String {
            config.theme = value
        }
        if let value = JSONValue.int(dict["terminalFontSize"]) {
            config.terminalFontSize = value
        }
        if let value = dict["terminalFontFamily"] as? String {
            config.terminalFontFamily = value
        }
        if let value = dict["terminalCursorStyle"] as? String {
            config.terminalCursorStyle = value
        }
        if let value = JSONValue.bool(dict["terminalCursorBlink"]) {
            config.terminalCursorBlink = value
        }
        config.notifications = NotificationSettingsCodec.decode(nested(dict, "notifications"))
        if let value = JSONValue.bool(dict["autoMinimizeOnSend"]) {
            config.autoMinimizeOnSend = value
        }
        config.sessionTrigger = SessionTriggerCodec.decode(nested(dict, "sessionTrigger"))
        config.usageAutoRefresh = UsageAutoRefreshCodec.decode(nested(dict, "usageAutoRefresh"))
        config.usageIndicators = UsageIndicatorsCodec.decode(nested(dict, "usageIndicators"))
        return config
    }

    static func overlay(_ config: AppConfig) -> [String: Any] {
        [
            "projectsRoot": config.projectsRoot,
            "additionalPaths": AdditionalPathCodec.overlayList(config.additionalPaths),
            "aiProvider": config.aiProvider.rawValue,
            "theme": config.theme,
            "terminalFontSize": config.terminalFontSize,
            "terminalFontFamily": config.terminalFontFamily,
            "terminalCursorStyle": config.terminalCursorStyle,
            "terminalCursorBlink": config.terminalCursorBlink,
            "notifications": NotificationSettingsCodec.overlay(config.notifications),
            "autoMinimizeOnSend": config.autoMinimizeOnSend,
            "sessionTrigger": SessionTriggerCodec.overlay(config.sessionTrigger),
            "usageAutoRefresh": UsageAutoRefreshCodec.overlay(config.usageAutoRefresh),
            "usageIndicators": UsageIndicatorsCodec.overlay(config.usageIndicators),
        ]
    }

    /// Alt bölüm sözlüğü; yoksa/yanlış tipliyse nil → alt codec default döner.
    private static func nested(_ dict: [String: Any], _ key: String) -> [String: Any]? {
        dict[key] as? [String: Any]
    }
}
