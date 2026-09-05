import Foundation
import LumiKit

/// Claude ve Codex `.jsonl` transkript satırlarını okunur oturum alanlarına
/// çevirir (Agent History detay kartı).
///
/// Girdi ham `JSONSerialization` sözlükleridir: `AgentHistoryService` dosyanın
/// baş + son örneğini okur, ayrıştırma burada yapılır. Böylece format bilgisi
/// dosya okuma stratejisinden ayrı ve doğrudan test edilebilir.
struct AgentTranscriptParser {
    /// Bir transkriptten çıkarılan alanlar.
    struct Transcript: Equatable {
        var cwd: String?
        var sessionID: String?
        var gitBranch: String?
        var model: String?
        var firstPrompt: String?
        var turns: [AgentHistoryTurn] = []

        /// Örneklenen kullanıcı+asistan mesaj sayısı (tool çağrıları hariç).
        var messageCount: Int { turns.count }
    }

    /// Metin blokları içinde konuşma sayılan tipler; `tool_use`, `tool_result`
    /// ve `thinking` blokları dışarıda kalır.
    private static let textBlockTypes: Set<String> = ["text", "input_text", "output_text"]

    /// CLI'ların transkripte yazdığı, kullanıcının yazmadığı sarmalayıcılar.
    private static let systemTextPrefixes = [
        "<environment_context>",
        "# AGENTS.md instructions",
        "<system-reminder>",
        "<command-name>",
        "<command-message>",
        "<local-command-stdout>",
        "<local-command-caveat>",
        "<recommended_plugins>",
        "<user_instructions>",
        "<task-notification>",
        "<user-prompt-submit-hook>",
        "<permissions instructions>",
    ]

    /// Tek turda saklanan en uzun metin — 200 oturum × 3 tur bellekte tutulur.
    private static let maxTurnLength = 4_000

    let provider: AgentProvider

    func parse(_ records: [[String: Any]]) -> Transcript {
        var transcript = Transcript()
        var seen: Set<String> = []
        for record in records {
            applyMetadata(record, to: &transcript)
            guard let turn = turn(in: record) else { continue }
            guard seen.insert("\(turn.role.rawValue)|\(turn.text)").inserted else { continue }
            transcript.turns.append(turn)
            if turn.role == .user, transcript.firstPrompt == nil { transcript.firstPrompt = turn.text }
        }
        return transcript
    }

    // MARK: - Metadata

    private func applyMetadata(_ record: [String: Any], to transcript: inout Transcript) {
        provider == .claude
            ? applyClaudeMetadata(record, to: &transcript)
            : applyCodexMetadata(record, to: &transcript)
    }

    private func applyClaudeMetadata(_ record: [String: Any], to transcript: inout Transcript) {
        assignIfMissing(&transcript.cwd, record["cwd"])
        assignIfMissing(&transcript.sessionID, record["sessionId"])
        assignIfMissing(&transcript.gitBranch, record["gitBranch"])
        // Model son asistan mesajından okunur: oturum ortasında değişebilir.
        guard record["type"] as? String == "assistant",
              let model = nonEmpty((record["message"] as? [String: Any])?["model"]) else { return }
        transcript.model = model
    }

    private func applyCodexMetadata(_ record: [String: Any], to transcript: inout Transcript) {
        guard let kind = record["type"] as? String,
              let payload = record["payload"] as? [String: Any] else { return }
        switch kind {
        case "session_meta":
            assignIfMissing(&transcript.cwd, payload["cwd"])
            assignIfMissing(&transcript.sessionID, payload["id"] ?? payload["session_id"])
            assignIfMissing(&transcript.gitBranch, (payload["git"] as? [String: Any])?["branch"])
            if let model = nonEmpty(payload["model"]) { transcript.model = model }
        case "turn_context":
            assignIfMissing(&transcript.cwd, payload["cwd"])
            if let model = nonEmpty(payload["model"]) { transcript.model = model }
        default:
            break
        }
    }

    private func assignIfMissing(_ target: inout String?, _ value: Any?) {
        guard target == nil, let value = nonEmpty(value) else { return }
        target = value
    }

    private func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Turlar

    private func turn(in record: [String: Any]) -> AgentHistoryTurn? {
        guard let candidate = role(in: record) else { return nil }
        guard let text = conversationText(candidate.content) else { return nil }
        return AgentHistoryTurn(
            role: candidate.role,
            text: String(text.prefix(Self.maxTurnLength)),
            timestamp: timestamp(record)
        )
    }

    private func role(in record: [String: Any]) -> (role: AgentHistoryTurn.Role, content: Any?)? {
        let kind = record["type"] as? String
        if provider == .claude {
            // `isMeta` satırları CLI'ın kendi notlarıdır, kullanıcı turu değil.
            guard record["isMeta"] as? Bool != true else { return nil }
            let content = (record["message"] as? [String: Any])?["content"]
            switch kind {
            case "user": return (.user, content)
            case "assistant": return (.assistant, content)
            default: return nil
            }
        }
        guard let payload = record["payload"] as? [String: Any] else { return nil }
        switch (kind, payload["type"] as? String) {
        case ("response_item", "message"):
            // `developer` rolü sistem yönergesidir; konuşmaya girmez.
            guard let role = AgentHistoryTurn.Role(rawValue: payload["role"] as? String ?? "") else { return nil }
            return (role, payload["content"])
        case ("event_msg", "user_message"):
            return (.user, payload["message"])
        case ("event_msg", "agent_message"):
            return (.assistant, payload["message"])
        default:
            return nil
        }
    }

    private func conversationText(_ content: Any?) -> String? {
        let text: String
        if let string = content as? String {
            text = string
        } else if let blocks = content as? [[String: Any]] {
            text = blocks.compactMap { block -> String? in
                guard let type = block["type"] as? String, Self.textBlockTypes.contains(type) else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
        } else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !Self.systemTextPrefixes.contains(where: trimmed.hasPrefix) else { return nil }
        return trimmed
    }

    private func timestamp(_ record: [String: Any]) -> Date? {
        guard let raw = record["timestamp"] as? String else { return nil }
        return (try? Self.isoWithFraction.parse(raw)) ?? (try? Self.iso.parse(raw))
    }

    // `ISO8601DateFormatter` Swift 6'da Sendable değil; format style değer tipi.
    private static let isoWithFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let iso = Date.ISO8601FormatStyle()
}
