import Foundation
import LumiWire

/// Bir stream-json NDJSON satırının tip'li karşılığı (spec 2026-09-17 Faz 1 §B).
/// Gerçek `claude --output-format stream-json` taksonomisine dayanır. Reducer'ın
/// umursadığı case'ler dışındaki her şey `.ignored` (akış ölmez).
public enum StreamJsonEvent: Equatable, Sendable {
    case systemInit(sessionID: String, cwd: String?)
    case streamTextDelta(String)
    case assistantSnapshot(id: String, blocks: [ChatBlock])
    case userEcho(id: String, blocks: [ChatBlock])
    case turnResult(costUSD: Double?, outputTokens: Int?)
    case rateLimit
    case ignored

    public static func decode(_ line: String) -> StreamJsonEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .ignored }
        switch obj["type"] as? String {
        case "system":
            guard obj["subtype"] as? String == "init", let sid = obj["session_id"] as? String else { return .ignored }
            return .systemInit(sessionID: sid, cwd: obj["cwd"] as? String)
        case "stream_event":
            guard let event = obj["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return .ignored }
            return .streamTextDelta(text)
        case "assistant":
            guard let msg = obj["message"] as? [String: Any], let id = msg["id"] as? String else { return .ignored }
            let blocks = ClaudeContentBlockDecoding.decodeBlocks(msg["content"])
            return .assistantSnapshot(id: id, blocks: blocks)
        case "user":
            guard let msg = obj["message"] as? [String: Any] else { return .ignored }
            // `--replay-user-messages` yankısı ve tool_result kayıtları
            // `message.id` taşımaz ama üst seviye `uuid` taşır (karar 114).
            let id = (msg["id"] as? String) ?? (obj["uuid"] as? String) ?? "user-\(UUID().uuidString)"
            let blocks = ClaudeContentBlockDecoding.decodeBlocks(msg["content"])
            return blocks.isEmpty ? .ignored : .userEcho(id: id, blocks: blocks)
        case "result":
            let cost = obj["total_cost_usd"] as? Double
            let tokens = (obj["usage"] as? [String: Any])?["output_tokens"] as? Int
            return .turnResult(costUSD: cost, outputTokens: tokens)
        case "rate_limit_event":
            return .rateLimit
        default:
            return .ignored
        }
    }
}
