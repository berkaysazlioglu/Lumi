import Foundation
import LumiKit

/// `config.json` → `sessionTrigger` ↔ `SessionTrigger`.
/// Saat/dakika clamp'i modelin init'indedir (tek doğrulama yeri).
enum SessionTriggerCodec {
    static func decode(_ dict: [String: Any]?) -> SessionTrigger {
        let defaults = SessionTrigger.defaults
        guard let dict else { return defaults }

        return SessionTrigger(
            enabled: JSONValue.bool(dict["enabled"]) ?? defaults.enabled,
            hour: JSONValue.int(dict["hour"]) ?? defaults.hour,
            minute: JSONValue.int(dict["minute"]) ?? defaults.minute,
            prompt: (dict["prompt"] as? String) ?? defaults.prompt
        )
    }

    static func overlay(_ trigger: SessionTrigger) -> [String: Any] {
        [
            "enabled": trigger.enabled,
            "hour": trigger.hour,
            "minute": trigger.minute,
            "prompt": trigger.prompt,
        ]
    }
}
