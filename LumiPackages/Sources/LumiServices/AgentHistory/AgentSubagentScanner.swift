import Foundation
import LumiKit

/// Claude oturumunun alt ajan transkriptlerini listeler:
/// `<projects>/<encoded>/<sessionId>/subagents/agent-<id>.jsonl` (+ `.meta.json`).
///
/// `meta.json` ad/tür/model verir; yoksa ad ilk istemin başından türetilir.
/// Mesaj sayısı satır tipleri sayılarak bulunur — dosya tamamen okunur ama
/// üst sınırla (büyük transkriptte sayı "en az" anlamına gelir).
struct AgentSubagentScanner {
    static let maxCountedBytes = 8 * 1024 * 1024
    static let fallbackNameLength = 80
    static let headBytes = 16 * 1024

    static func scan(sessionLog: URL) -> [AgentHistorySubagent] {
        let directory = sessionLog.deletingPathExtension().appendingPathComponent("subagents")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return items
            .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-") }
            .sorted { modified($0) > modified($1) }
            .compactMap(read)
    }

    static func read(_ log: URL) -> AgentHistorySubagent? {
        let id = String(log.deletingPathExtension().lastPathComponent.dropFirst("agent-".count))
        guard !id.isEmpty, let data = FileManager.default.contents(atPath: log.path) else { return nil }
        let meta = readMeta(log.deletingPathExtension().appendingPathExtension("meta.json"))
        let name = meta?["description"] as? String ?? fallbackName(data) ?? "Subagent"
        return AgentHistorySubagent(
            id: id,
            name: String(name.prefix(fallbackNameLength)),
            kind: meta?["agentType"] as? String,
            model: meta?["model"] as? String,
            messageCount: countMessages(data),
            logPath: log.path
        )
    }

    private static func readMeta(_ url: URL) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// `"type":"user"` ve `"type":"assistant"` kayıtlarını sayar.
    static func countMessages(_ data: Data) -> Int {
        let sample = data.prefix(maxCountedBytes)
        return occurrences(of: Data("\"type\":\"user\"".utf8), in: sample)
            + occurrences(of: Data("\"type\":\"assistant\"".utf8), in: sample)
    }

    private static func occurrences(of needle: Data, in haystack: Data) -> Int {
        var count = 0
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, in: searchRange) {
            count += 1
            searchRange = found.upperBound..<haystack.endIndex
        }
        return count
    }

    /// İlk kaydın kullanıcı metni (meta yoksa ad olarak kullanılır).
    private static func fallbackName(_ data: Data) -> String? {
        let head = data.prefix(headBytes)
        guard let newline = head.firstIndex(of: 10) else { return firstUserText(head) }
        return firstUserText(head[head.startIndex..<newline])
    }

    private static func firstUserText(_ line: Data) -> String? {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let content = (record["message"] as? [String: Any])?["content"] else { return nil }
        let text: String?
        if let string = content as? String {
            text = string
        } else if let blocks = content as? [[String: Any]] {
            text = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        } else {
            text = nil
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
