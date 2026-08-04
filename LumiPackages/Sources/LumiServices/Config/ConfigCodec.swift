import Foundation
import LumiKit

/// Diskteki JSON ↔ tipli model çevirisi (karar 9'un teknik kalbi).
///
/// Codable yerine ham-dict + tipli-overlay: gerçek dosyalarda spec dışı/legacy
/// alanlar yaşar (`gridColumns`, `activeView`) ve Electron'un `{...existing,
/// ...partial}` merge'i bunları korur. Native yazım da bilinmeyen anahtarları
/// AYNEN korumalıdır, yoksa Electron'la gidip-gelme bozulur.
///
/// Decode lenient'tır (Electron migration kuralları, spec/13 §1.1): yanlış
/// tipli alan default'a düşer, `additionalPaths` array değilse `[]` olur,
/// geçersiz `aiProvider` claude'a döner.
enum ConfigCodec {
    // MARK: - AppConfig

    static func decodeConfig(from dict: [String: Any]?) -> AppConfig {
        var config = AppConfig.defaults
        guard let dict else { return config }

        if let value = dict["projectsRoot"] as? String {
            config.projectsRoot = value
        }
        config.additionalPaths = decodeAdditionalPaths(dict["additionalPaths"])
        if let raw = dict["aiProvider"] as? String,
           let provider = AgentProvider(rawValue: raw) {
            config.aiProvider = provider
        }
        if let value = intValue(dict["maxTerminals"]) {
            config.maxTerminals = value
        }
        if let value = dict["theme"] as? String {
            config.theme = value
        }
        if let value = intValue(dict["terminalFontSize"]) {
            config.terminalFontSize = value
        }
        if let value = boolValue(dict["terminalFontSmoothing"]) {
            config.terminalFontSmoothing = value
        }
        if let value = dict["terminalTheme"] as? String {
            config.terminalTheme = value
        }
        if let value = dict["terminalFontFamily"] as? String {
            config.terminalFontFamily = value
        }
        if let value = dict["terminalCursorStyle"] as? String {
            config.terminalCursorStyle = value
        }
        if let value = boolValue(dict["terminalCursorBlink"]) {
            config.terminalCursorBlink = value
        }
        if let nested = dict["notifications"] as? [String: Any] {
            var settings = NotificationSettings.defaults
            if let value = boolValue(nested["unseenEnabled"]) { settings.unseenEnabled = value }
            if let value = intValue(nested["unseenIntervalMinutes"]) { settings.unseenIntervalMinutes = value }
            if let value = boolValue(nested["seenEnabled"]) { settings.seenEnabled = value }
            if let value = intValue(nested["seenIntervalMinutes"]) { settings.seenIntervalMinutes = value }
            config.notifications = settings
        }
        if let nested = dict["sessionTrigger"] as? [String: Any] {
            let defaults = SessionTrigger.defaults
            config.sessionTrigger = SessionTrigger(
                enabled: boolValue(nested["enabled"]) ?? defaults.enabled,
                hour: intValue(nested["hour"]) ?? defaults.hour,
                minute: intValue(nested["minute"]) ?? defaults.minute,
                prompt: (nested["prompt"] as? String) ?? defaults.prompt
            )
        }
        if let nested = dict["usageAutoRefresh"] as? [String: Any] {
            let defaults = UsageAutoRefresh.defaults
            config.usageAutoRefresh = UsageAutoRefresh(
                enabled: boolValue(nested["enabled"]) ?? defaults.enabled,
                intervalMinutes: intValue(nested["intervalMinutes"]) ?? defaults.intervalMinutes
            )
        }
        return config
    }

    static func configOverlay(_ config: AppConfig) -> [String: Any] {
        [
            "projectsRoot": config.projectsRoot,
            "additionalPaths": config.additionalPaths.map { path -> [String: Any] in
                var entry: [String: Any] = [
                    "id": path.id,
                    "path": path.path,
                    "type": path.type.rawValue,
                ]
                if let label = path.label {
                    entry["label"] = label
                }
                return entry
            },
            "aiProvider": config.aiProvider.rawValue,
            "maxTerminals": config.maxTerminals,
            "theme": config.theme,
            "terminalFontSize": config.terminalFontSize,
            "terminalFontSmoothing": config.terminalFontSmoothing,
            "terminalTheme": config.terminalTheme,
            "terminalFontFamily": config.terminalFontFamily,
            "terminalCursorStyle": config.terminalCursorStyle,
            "terminalCursorBlink": config.terminalCursorBlink,
            "notifications": [
                "unseenEnabled": config.notifications.unseenEnabled,
                "unseenIntervalMinutes": config.notifications.unseenIntervalMinutes,
                "seenEnabled": config.notifications.seenEnabled,
                "seenIntervalMinutes": config.notifications.seenIntervalMinutes,
            ] as [String: Any],
            "sessionTrigger": [
                "enabled": config.sessionTrigger.enabled,
                "hour": config.sessionTrigger.hour,
                "minute": config.sessionTrigger.minute,
                "prompt": config.sessionTrigger.prompt,
            ] as [String: Any],
            "usageAutoRefresh": [
                "enabled": config.usageAutoRefresh.enabled,
                "intervalMinutes": config.usageAutoRefresh.intervalMinutes,
            ] as [String: Any],
        ]
    }

    private static func decodeAdditionalPaths(_ value: Any?) -> [AdditionalPath] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { element in
            guard let dict = element as? [String: Any],
                  let id = dict["id"] as? String,
                  let path = dict["path"] as? String,
                  let typeRaw = dict["type"] as? String,
                  let type = AdditionalPath.PathType(rawValue: typeRaw) else {
                return nil
            }
            return AdditionalPath(id: id, path: path, type: type, label: dict["label"] as? String)
        }
    }

    // MARK: - UIState

    static func decodeUIState(from dict: [String: Any]?) -> UIState {
        var state = UIState.defaults
        guard let dict else { return state }

        if let value = dict["openTabs"] as? [Any] {
            state.openTabs = value.compactMap { $0 as? String }
        }
        if let value = dict["activeTab"] as? String {
            state.activeTab = value
        }
        if let value = boolValue(dict["leftSidebarOpen"]) {
            state.leftSidebarOpen = value
        }
        if let value = boolValue(dict["rightSidebarOpen"]) {
            state.rightSidebarOpen = value
        }
        if let layouts = dict["projectGridLayouts"] as? [String: Any] {
            state.projectGridLayouts = layouts.compactMapValues { entry in
                guard let dict = entry as? [String: Any],
                      let modeRaw = dict["mode"] as? String,
                      let count = intValue(dict["count"]) else {
                    return nil
                }
                // Emekli `rows` modu → auto + fit migrasyonu (eski/v1 dosyaları).
                if modeRaw == "rows" {
                    return GridLayout(mode: .auto, count: count, heightMode: .fit)
                }
                guard let mode = GridLayout.Mode(rawValue: modeRaw) else { return nil }
                // heightMode yoksa eski algılanan davranış: auto/columns scroll'du.
                let heightMode = (dict["heightMode"] as? String)
                    .flatMap(GridLayout.HeightMode.init(rawValue:)) ?? .scroll
                let heightRatio = (dict["heightRatio"] as? String)
                    .flatMap(GridLayout.HeightRatio.init(rawValue:)) ?? .half
                return GridLayout(mode: mode, count: count, heightMode: heightMode, heightRatio: heightRatio)
            }
        }
        if let bounds = dict["windowBounds"] as? [String: Any],
           let x = doubleValue(bounds["x"]),
           let y = doubleValue(bounds["y"]),
           let width = doubleValue(bounds["width"]),
           let height = doubleValue(bounds["height"]) {
            state.windowBounds = WindowBounds(x: x, y: y, width: width, height: height)
        }
        if let value = boolValue(dict["windowMaximized"]) {
            state.windowMaximized = value
        }
        // Karar 23 (additive): açılışta tüketilecek claude resume kayıtları
        if let raw = dict["resumeSessions"] as? [[String: Any]] {
            state.resumeSessions = raw.compactMap { entry in
                guard let repoPath = entry["repoPath"] as? String,
                      let sessionID = entry["sessionID"] as? String else { return nil }
                return ResumeSession(repoPath: repoPath, sessionID: sessionID)
            }
        }
        // Legacy global gridColumns: "auto" | number → migration girdisi (spec/21 §13)
        if let legacy = dict["gridColumns"] {
            if let text = legacy as? String, text == "auto" {
                state.legacyGridColumns = GridLayout(mode: .auto, count: 2)
            } else if let count = intValue(legacy) {
                state.legacyGridColumns = GridLayout(mode: .columns, count: min(max(count, 2), 5))
            }
        }
        return state
    }

    static func uiStateOverlay(_ state: UIState) -> [String: Any] {
        var overlay: [String: Any] = [
            // activeTab nil → açıkça null yazılır (gerçek dosya paritesi)
            "activeTab": state.activeTab ?? NSNull(),
            "openTabs": state.openTabs,
            "leftSidebarOpen": state.leftSidebarOpen,
            "rightSidebarOpen": state.rightSidebarOpen,
            "projectGridLayouts": state.projectGridLayouts.mapValues { layout -> [String: Any] in
                // mode/count korunur (karar 9), heightMode/heightRatio eklenir (additive).
                ["mode": layout.mode.rawValue, "count": layout.count,
                 "heightMode": layout.heightMode.rawValue,
                 "heightRatio": layout.heightRatio.rawValue]
            },
            // Karar 23: HER yazımda overlay'e girer — koşullu yazılsaydı merge
            // tüketilmiş (boşaltılmış) listeyi diskte bayat bırakırdı.
            "resumeSessions": state.resumeSessions.map { entry in
                ["repoPath": entry.repoPath, "sessionID": entry.sessionID]
            },
        ]
        if let bounds = state.windowBounds {
            overlay["windowBounds"] = [
                "x": integralNumber(bounds.x),
                "y": integralNumber(bounds.y),
                "width": integralNumber(bounds.width),
                "height": integralNumber(bounds.height),
            ] as [String: Any]
        }
        if let maximized = state.windowMaximized {
            overlay["windowMaximized"] = maximized
        }
        return overlay
    }

    // MARK: - Lenient sayı/bool yardımcıları

    /// JSONSerialization bool'ları da NSNumber'dır; sayı alanına bool sızmasın.
    static func intValue(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number.intValue
    }

    static func doubleValue(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        return number.doubleValue
    }

    static func boolValue(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Tam sayı değerler Electron gibi "580" yazılsın, "580.0" değil.
    private static func integralNumber(_ value: Double) -> Any {
        value.truncatingRemainder(dividingBy: 1) == 0 ? Int(value) : value
    }
}
