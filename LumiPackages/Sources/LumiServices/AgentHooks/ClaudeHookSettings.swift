import Foundation
import LumiKit

/// `~/.claude/settings.json` içindeki `hooks` bölümünün saf düzenleyicisi
/// (karar 45; Orca `applyManagedHooks` / `removeManagedHooks` mantığı).
///
/// Kullanıcının kendi hook'larına dokunulmaz; yalnız Lumi'nin yönetilen komutu
/// eklenir/kaldırılır. Aynı event'te eski bir Lumi komutu (taşınmış ev dizini,
/// silinmiş script) varsa süpürülür.
enum ClaudeHookSettings {
    /// Kaydedilen event'ler ve `matcher` ihtiyacı (araç event'leri `*`).
    static let events: [(name: String, matcher: String?)] = [
        // SessionStart: sürdürülen/boşta oturumun ilk istemden önce yaydığı tek
        // sinyal; SessionEnd: ajan çıktı, geride düz shell kaldı.
        ("SessionStart", nil),
        ("SessionEnd", nil),
        ("UserPromptSubmit", nil),
        ("Stop", nil),
        // OpenClaude API hatasında Stop yerine StopFailure yayar; Claude
        // tanımadığı adı yok sayar.
        ("StopFailure", nil),
        ("SubagentStart", nil),
        ("SubagentStop", nil),
        ("TeammateIdle", nil),
        ("PreToolUse", "*"),
        ("PostToolUse", "*"),
        ("PostToolUseFailure", "*"),
        ("PermissionRequest", "*"),
        // Manuel /compact idle prompt'ta biter ve Stop yaymaz; PreCompact bilerek
        // kayıtlı değil (iptal edilen compact tek başına onu yayar).
        ("PostCompact", nil),
    ]

    /// Hook komutunun tamamlanma bütçesi (curl 1.5 s'de döner).
    static let timeoutSeconds = 10

    static func managedHook(command: String) -> [String: Any] {
        ["type": "command", "command": command, "timeout": timeoutSeconds]
    }

    /// Yönetilen komutu tüm event'lere ekler; Lumi'nin eski komutlarını süpürür.
    /// Dönüş: yeni kök nesne + değişti mi.
    static func applyManaged(
        to root: [String: Any],
        command: String,
        isStale: (String) -> Bool
    ) -> (root: [String: Any], changed: Bool) {
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for event in events {
            let current = hooks[event.name] as? [[String: Any]] ?? []
            let cleaned = removingLumiCommands(from: current, isStale: isStale, keepExact: command)
            let alreadyPresent = cleaned.contains { group in
                (group["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String) == command } == true
                    && (group["matcher"] as? String) == event.matcher
            }
            var next = cleaned
            if !alreadyPresent {
                var group: [String: Any] = ["hooks": [managedHook(command: command)]]
                if let matcher = event.matcher { group["matcher"] = matcher }
                next.append(group)
            }
            if !isEquivalent(next, current) {
                changed = true
                hooks[event.name] = next
            }
        }
        var result = root
        result["hooks"] = hooks
        return (result, changed)
    }

    /// Tüm Lumi komutlarını (güncel dahil) kaldırır.
    static func removeManaged(from root: [String: Any]) -> (root: [String: Any], changed: Bool) {
        guard var hooks = root["hooks"] as? [String: Any] else { return (root, false) }
        var changed = false
        for (name, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let cleaned = removingLumiCommands(from: groups, isStale: { _ in true }, keepExact: nil)
            guard !isEquivalent(cleaned, groups) else { continue }
            changed = true
            if cleaned.isEmpty {
                hooks.removeValue(forKey: name)
            } else {
                hooks[name] = cleaned
            }
        }
        var result = root
        result["hooks"] = hooks
        return (result, changed)
    }

    /// Lumi'ye ait komut mu (script iğnesi).
    static func isLumiCommand(_ command: String) -> Bool {
        command.contains(AgentHookScript.managedNeedle(for: .claude))
    }

    // MARK: - Yardımcılar

    /// Grup içindeki Lumi komutlarını süzer: `keepExact` korunur, diğer Lumi
    /// komutları `isStale` derse düşer; Lumi komutu kalmayan grup silinir.
    private static func removingLumiCommands(
        from groups: [[String: Any]],
        isStale: (String) -> Bool,
        keepExact: String?
    ) -> [[String: Any]] {
        groups.compactMap { group in
            guard let entries = group["hooks"] as? [[String: Any]] else { return group }
            let kept = entries.filter { entry in
                guard let command = entry["command"] as? String, isLumiCommand(command) else { return true }
                if let keepExact, command == keepExact { return true }
                return !isStale(command)
            }
            guard kept.count != entries.count else { return group }
            guard !kept.isEmpty else { return nil }
            var copy = group
            copy["hooks"] = kept
            return copy
        }
    }

    private static func isEquivalent(_ lhs: [[String: Any]], _ rhs: [[String: Any]]) -> Bool {
        NSArray(array: lhs).isEqual(to: rhs)
    }
}
