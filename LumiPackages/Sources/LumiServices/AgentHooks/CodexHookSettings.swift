import Foundation
import LumiKit

/// `~/.codex/hooks.json` saf düzenleyicisi (karar 45). Codex bilinmeyen üst
/// düzey alanları reddeder: dosya yalnız `{"hooks": {...}}` taşır.
enum CodexHookSettings {
    /// Orca `CODEX_EVENTS`: Pre/PostToolUse canlı araç bilgisini, PermissionRequest
    /// karar bekleme sinyalini besler (hook karar vermez, Codex kendi onay
    /// arayüzünü gösterir).
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
        "PostToolUse", "SubagentStart", "SubagentStop", "Stop",
    ]
    static let timeoutSeconds = 10

    static func managedHook(command: String) -> [String: Any] {
        ["type": "command", "command": command, "timeout": timeoutSeconds]
    }

    static func isLumiCommand(_ command: String) -> Bool {
        command.contains(AgentHookScript.managedNeedle(for: .codex))
    }

    /// Yönetilen grubu her event'e ekler; eski Lumi gruplarını süpürür.
    /// Dönüş: yeni kök, değişti mi, event → bizim grubun indeksi (güven anahtarı için).
    static func applyManaged(
        to root: [String: Any],
        command: String
    ) -> (root: [String: Any], changed: Bool, groupIndex: [String: Int]) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        var indices: [String: Int] = [:]
        for event in events {
            let current = hooks[event] as? [[String: Any]] ?? []
            var next = current.filter { group in
                !(group["hooks"] as? [[String: Any]] ?? []).contains { entry in
                    guard let existing = entry["command"] as? String, isLumiCommand(existing) else { return false }
                    return existing != command
                }
            }
            if let index = next.firstIndex(where: { isOurGroup($0, command: command) }) {
                indices[event] = index
            } else {
                next.append(["hooks": [managedHook(command: command)]])
                indices[event] = next.count - 1
            }
            if !NSArray(array: next).isEqual(to: current) {
                changed = true
                hooks[event] = next
            }
        }
        return (["hooks": hooks], changed, indices)
    }

    static func removeManaged(from root: [String: Any]) -> (root: [String: Any], changed: Bool) {
        guard var hooks = root["hooks"] as? [String: Any] else { return (root, false) }
        var changed = false
        for (name, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned = groups.filter { group in
                !(group["hooks"] as? [[String: Any]] ?? []).contains {
                    ($0["command"] as? String).map(isLumiCommand) == true
                }
            }
            guard cleaned.count != groups.count else { continue }
            changed = true
            if cleaned.isEmpty {
                hooks.removeValue(forKey: name)
            } else {
                hooks[name] = cleaned
            }
        }
        return (["hooks": hooks], changed)
    }

    private static func isOurGroup(_ group: [String: Any], command: String) -> Bool {
        guard let entries = group["hooks"] as? [[String: Any]], entries.count == 1,
              let existing = entries[0]["command"] as? String else { return false }
        return existing == command && group["matcher"] == nil
    }
}
