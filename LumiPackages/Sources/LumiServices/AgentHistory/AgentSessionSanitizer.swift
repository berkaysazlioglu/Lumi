import Foundation

/// Dışa aktarılan Claude transkriptinden kişisel/makineye özgü kayıtları ayıklar.
///
/// Neler düşer (gerçek kayıtların incelenmesiyle, karar 52):
/// - `attachment` kayıtları **allowlist** dışındaysa: `session_context` (e-posta),
///   `instructions` (CLAUDE.md içerikleri), `nested_memory` (bellek dosyaları),
///   `environment`, `prompt_snapshot`, `skill_listing`, hook çıktıları, araç/MCP
///   listeleri… Bunlar oturum açılışında CLI tarafından yeniden üretilir.
/// - `cost-state` (USD maliyet), `file-history-*` (yerel yedek yolları),
///   `atis-latch`, `frame-link`, `artifact-comment-monitor`.
/// - `system` kayıtlarından `stop_hook_summary` (hook komutları).
///
/// Kalan kayıtların `parentUuid` / `leafUuid` / `logicalParentUuid` zinciri
/// düşen kayıtların üstünden atlatılır; resume için ağaç bütün kalır.
struct AgentSessionSanitizer {
    static let keptAttachmentTypes: Set<String> = [
        "file", "edited_text_file", "queued_command", "task_reminder", "plan_mode", "plan_mode_exit",
        "diagnostics", "compact_file_reference", "invoked_skills", "date_change",
        "max_turns_reached", "read_truncation_notice",
    ]
    static let droppedRecordTypes: Set<String> = [
        "cost-state", "file-history-snapshot", "file-history-delta", "atis-latch",
        "frame-link", "artifact-comment-monitor",
    ]
    static let droppedSystemSubtypes: Set<String> = ["stop_hook_summary"]
    static let chainFields = ["parentUuid", "leafUuid", "logicalParentUuid"]

    static func sanitize(_ records: [[String: Any]]) -> [[String: Any]] {
        var redirect: [String: String?] = [:]
        var kept: [[String: Any]] = []
        for record in records {
            if shouldDrop(record) {
                if let uuid = record["uuid"] as? String { redirect[uuid] = record["parentUuid"] as? String }
                continue
            }
            kept.append(record)
        }
        guard !redirect.isEmpty else { return kept }
        return kept.map { relink($0, redirect: redirect) }
    }

    static func shouldDrop(_ record: [String: Any]) -> Bool {
        guard let type = record["type"] as? String else { return false }
        if droppedRecordTypes.contains(type) { return true }
        if type == "attachment" {
            let kind = (record["attachment"] as? [String: Any])?["type"] as? String
            return !(kind.map(keptAttachmentTypes.contains) ?? false)
        }
        if type == "system", let subtype = record["subtype"] as? String {
            return droppedSystemSubtypes.contains(subtype)
        }
        return false
    }

    private static func relink(_ record: [String: Any], redirect: [String: String?]) -> [String: Any] {
        var copy = record
        for field in chainFields {
            guard let current = record[field] as? String else { continue }
            copy[field] = resolve(current, redirect: redirect) as Any? ?? NSNull()
        }
        return copy
    }

    /// Düşen kayıtlar zinciri boyunca ilk kalan atayı bulur (döngü korumalı).
    private static func resolve(_ uuid: String, redirect: [String: String?]) -> String? {
        var current: String? = uuid
        var hops = 0
        while let value = current, let next = redirect[value], hops < redirect.count + 1 {
            current = next
            hops += 1
        }
        return current
    }
}
