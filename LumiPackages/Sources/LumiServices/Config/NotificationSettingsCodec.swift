import Foundation
import LumiKit

/// `config.json` → `notifications` ↔ `NotificationSettings`.
///
/// `agentFinished`/`needsInput`/`sound` karar 145'ün additive anahtarlarıdır;
/// eski tekrar anahtarları okunup aynen geri yazılır.
enum NotificationSettingsCodec {
    static func decode(_ dict: [String: Any]?) -> NotificationSettings {
        var settings = NotificationSettings.defaults
        guard let dict else { return settings }

        if let value = JSONValue.bool(dict["agentFinished"]) { settings.agentFinished = value }
        if let value = JSONValue.bool(dict["needsInput"]) { settings.needsInput = value }
        if let value = JSONValue.bool(dict["sound"]) { settings.sound = value }
        if let value = JSONValue.bool(dict["unseenEnabled"]) { settings.unseenEnabled = value }
        if let value = JSONValue.int(dict["unseenIntervalMinutes"]) { settings.unseenIntervalMinutes = value }
        if let value = JSONValue.bool(dict["seenEnabled"]) { settings.seenEnabled = value }
        if let value = JSONValue.int(dict["seenIntervalMinutes"]) { settings.seenIntervalMinutes = value }
        return settings
    }

    static func overlay(_ settings: NotificationSettings) -> [String: Any] {
        [
            "agentFinished": settings.agentFinished,
            "needsInput": settings.needsInput,
            "sound": settings.sound,
            "unseenEnabled": settings.unseenEnabled,
            "unseenIntervalMinutes": settings.unseenIntervalMinutes,
            "seenEnabled": settings.seenEnabled,
            "seenIntervalMinutes": settings.seenIntervalMinutes,
        ]
    }
}
