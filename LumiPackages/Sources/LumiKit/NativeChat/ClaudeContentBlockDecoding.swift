import Foundation
import LumiWire

/// Anthropic mesaj `content` dizisini `ChatBlock`'lara çeviren paylaşılan saf
/// yardımcı. Hem transcript JSONL decoder'ı hem stream-json `assistant` snapshot'ı
/// aynı blok şeklini gördüğü için tek kaynak (spec 2026-09-17 Faz 1 §B).
public enum ClaudeContentBlockDecoding {
    private static let maxPreview = 200
    private static let maxOutput = 4000

    public static func decodeBlocks(_ content: Any?) -> [ChatBlock] {
        if let string = content as? String {
            let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [.text(t, presentation: nil)]
        }
        guard let blocks = content as? [[String: Any]] else { return [] }
        return blocks.compactMap(decodeBlock)
    }

    public static func decodeBlock(_ block: [String: Any]) -> ChatBlock? {
        switch block["type"] as? String {
        case "text":
            guard let text = (block["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return .text(text, presentation: nil)
        case "tool_use":
            let name = block["name"] as? String ?? "tool"
            return .toolCall(name: name, inputPreview: preview(block["input"]), state: "completed")
        case "tool_result":
            return .toolResult(output: output(block["content"]),
                               isError: block["is_error"] as? Bool ?? false)
        default:
            return nil   // thinking + tanınmayan → gösterilmez
        }
    }

    /// Claude TUI'nin `Bash(git status)` / `Read(path)` satırındaki birincil
    /// argüman (telefon chat'i TUI paritesi, 2026-10-23). Tanınan anahtar
    /// yoksa tüm girdiler `anahtar=değer` olarak sıralanır.
    static let primaryInputKeys = [
        "command", "file_path", "notebook_path", "pattern", "url", "query",
        "path", "description", "prompt", "skill",
    ]

    private static func preview(_ input: Any?) -> String {
        let text: String
        if let s = input as? String { text = s }
        else if let d = input as? [String: Any] {
            if let key = primaryInputKeys.first(where: { d[$0] is String }), let value = d[key] as? String {
                text = value
            } else {
                text = d.map { "\($0.key)=\(flatten($0.value))" }.sorted().joined(separator: " ")
            }
        } else { text = "" }
        return String(text.prefix(maxPreview))
    }

    private static func output(_ content: Any?) -> String {
        let text: String
        if let s = content as? String { text = s }
        else if let blocks = content as? [[String: Any]] {
            text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else { text = "" }
        return String(text.prefix(maxOutput))
    }

    private static func flatten(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return String(describing: value).prefix(80).description
    }
}
