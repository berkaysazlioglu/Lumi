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
        config.sidebarProjectPaths = decodeAbsoluteUniquePaths(dict["sidebarProjectPaths"])
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
        config.computerAwakeMode = ComputerAwakeMode.normalized(dict["computerAwakeMode"] as? String)
        if let value = JSONValue.bool(dict["agentHooksEnabled"]) {
            config.agentHooksEnabled = value
        }
        if let value = JSONValue.bool(dict["terminalLinkActionsEnabled"]) {
            config.terminalLinkActionsEnabled = value
        }
        config.claudeAccounts = ClaudeAccountCodec.decodeList(dict["claudeAccounts"])
        config.claudeAccountSelection = ClaudeAccountCodec.decodeSelection(
            dict["activeClaudeAccountId"], accounts: config.claudeAccounts
        )
        config.codexAccounts = CodexAccountCodec.decodeList(dict["codexAccounts"])
        config.codexAccountSelection = CodexAccountCodec.decodeSelection(
            dict["activeCodexAccountId"], accounts: config.codexAccounts
        )
        config.indexShortcutStyle = IndexShortcutStyle.normalized(
            dict["indexShortcutStyle"] as? String
        )
        config.workspaces = ProjectWorkspaceCodec.decodeList(dict["workspaces"])
        config.projectQuickCommands = QuickCommandCodec.decodeList(dict["projectQuickCommands"])
        return config
    }

    static func overlay(_ config: AppConfig) -> [String: Any] {
        var overlay: [String: Any] = [
            "projectsRoot": config.projectsRoot,
            "additionalPaths": AdditionalPathCodec.overlayList(config.additionalPaths),
            "sidebarProjectPaths": config.sidebarProjectPaths,
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
            "computerAwakeMode": config.computerAwakeMode.rawValue,
            "agentHooksEnabled": config.agentHooksEnabled,
            "terminalLinkActionsEnabled": config.terminalLinkActionsEnabled,
            "claudeAccounts": ClaudeAccountCodec.overlayList(config.claudeAccounts),
            "codexAccounts": CodexAccountCodec.overlayList(config.codexAccounts),
            "indexShortcutStyle": config.indexShortcutStyle.rawValue,
            "workspaces": ProjectWorkspaceCodec.overlayList(config.workspaces),
            "projectQuickCommands": QuickCommandCodec.overlayList(config.projectQuickCommands),
        ]
        // Sistem varsayılanı `null` olarak yazılır: anahtarı silmek, ham-dict
        // merge'inde eski seçimi diskte bırakırdı (karar 9).
        overlay["activeClaudeAccountId"] = config.claudeAccountSelection.accountID ?? NSNull()
        overlay["activeCodexAccountId"] = config.codexAccountSelection.accountID ?? NSNull()
        return overlay
    }

    /// Alt bölüm sözlüğü; yoksa/yanlış tipliyse nil → alt codec default döner.
    private static func nested(_ dict: [String: Any], _ key: String) -> [String: Any]? {
        dict[key] as? [String: Any]
    }

    private static func decodeAbsoluteUniquePaths(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        var seen = Set<String>()
        return values.compactMap { value in
            guard let path = value as? String,
                  !path.isEmpty,
                  (path as NSString).isAbsolutePath,
                  seen.insert(path).inserted else { return nil }
            return path
        }
    }
}
