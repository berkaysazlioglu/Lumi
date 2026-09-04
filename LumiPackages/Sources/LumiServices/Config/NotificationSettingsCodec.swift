import Foundation
import LumiKit

/// `config.json` → `notifications` ↔ `NotificationSettings`.
enum NotificationSettingsCodec {
    static func decode(_ dict: [String: Any]?) -> NotificationSettings {
        var settings = NotificationSettings.defaults
        guard let dict else { return settings }

        if let value = JSONValue.bool(dict["unseenEnabled"]) { settings.unseenEnabled = value }
        if let value = JSONValue.int(dict["unseenIntervalMinutes"]) { settings.unseenIntervalMinutes = value }
        if let value = JSONValue.bool(dict["seenEnabled"]) { settings.seenEnabled = value }
        if let value = JSONValue.int(dict["seenIntervalMinutes"]) { settings.seenIntervalMinutes = value }
        return settings
    }

    static func overlay(_ settings: NotificationSettings) -> [String: Any] {
        [
            "unseenEnabled": settings.unseenEnabled,
            "unseenIntervalMinutes": settings.unseenIntervalMinutes,
            "seenEnabled": settings.seenEnabled,
            "seenIntervalMinutes": settings.seenIntervalMinutes,
        ]
    }
}
