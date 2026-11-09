import Foundation
import LumiKit

extension TerminalTranscriptReading {
    /// Terminalin Claude oturumundaki son metinli asistan mesajı; oturum
    /// kimliği ya da transkript yoksa nil. Orchestrator özetleri (karar 114)
    /// ve bildirim gövdesi (karar 145) aynı kaynağı okur.
    func lastClaudeAssistantText(of meta: TerminalMeta) async -> String? {
        guard let sessionID = meta.claudeSessionID else { return nil }
        let messages = await recentClaudeMessages(sessionID: sessionID, cwd: meta.repoPath)
        return messages.last { $0.role == .assistant && !$0.plainText.isEmpty }?.plainText
    }
}

extension ChatMessage {
    /// Metin bloklarının birleşimi (araç çağrı/sonuçları hariç).
    var plainText: String {
        blocks.compactMap { block -> String? in
            if case let .text(text, _) = block { return text }
            return nil
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
