import Foundation
import LumiKit

/// Claude transcript JSONL satırını `ChatMessage`'a çevirir (orca
/// `transcript-line-decoders-claude.ts` Faz 1 alt kümesi). Blok-farkındalıklı:
/// `message.content` dizisini text/tool_use/tool_result olarak yürür.
/// Blok çözümü `ClaudeContentBlockDecoding` paylaşılan yardımcısına delege edilir.
struct ClaudeTranscriptChatDecoder {
    func decode(_ record: [String: Any], index: Int) -> ChatMessage? {
        guard record["isMeta"] as? Bool != true else { return nil }
        let kind = record["type"] as? String
        let role: ChatRole
        switch kind {
        case "user": role = .user
        case "assistant": role = .assistant
        default: return nil
        }
        let content = (record["message"] as? [String: Any])?["content"]
        var blocks = ClaudeContentBlockDecoding.decodeBlocks(content)
        guard !blocks.isEmpty else { return nil }
        if role == .user {
            guard let visible = Self.visibleUserBlocks(blocks) else { return nil }
            blocks = visible
        }
        let id = (record["uuid"] as? String) ?? "idx-\(index)"
        return ChatMessage(
            id: id, role: role, blocks: blocks,
            timestampMs: timestampMs(record["timestamp"] as? String),
            turnId: id
        )
    }

    /// Karar 95: harness'in eklediği user turları (`/clear` zarfı, yerel komut
    /// çıktısı, system-reminder…) chat'te gösterilmez; skill zarfı `/name args`
    /// olarak görünür. Yalnız düz metinden oluşan turlar sınıflandırılır —
    /// tool_result taşıyan user kayıtları olduğu gibi kalır.
    static func visibleUserBlocks(_ blocks: [ChatBlock]) -> [ChatBlock]? {
        var texts: [String] = []
        for block in blocks {
            guard case let .text(text, _) = block else { return blocks }
            texts.append(text)
        }
        let joined = texts.joined(separator: "\n")
        guard let display = HarnessInjectedTurn.displayText(forUserText: joined) else { return nil }
        return display == joined ? blocks : [.text(display, presentation: nil)]
    }

    private func timestampMs(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let styles = [Date.ISO8601FormatStyle(includingFractionalSeconds: true),
                      Date.ISO8601FormatStyle()]
        for style in styles {
            if let date = try? style.parse(raw) {
                return Int(date.timeIntervalSince1970 * 1000)
            }
        }
        return nil
    }
}
