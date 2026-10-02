import Foundation
import LumiKit

/// `watch_terminal` / `unwatch_terminal` (karar 103): yalnız izlenen
/// terminallerin bitişleri özetlenir. Sonradan izlemeye alınan terminalin o
/// ana kadarki oturumu bir haiku ajanına özetletilir — orchestrator'ın kendi
/// bağlamı transkriptle dolmaz. Okuma olduğu için onay istemez.
extension OrchestratorToolbox {
    /// Oturum özetine giden son metinli mesaj sayısı.
    static let catchUpMessageLimit = 40

    func watchTerminal(_ args: [String: Any]) async -> OrchestratorToolResult {
        guard let rawID = args["terminal_id"] as? String, !rawID.isEmpty else {
            return .failure("terminal_id is required.")
        }
        let meta: TerminalMeta
        switch resolveTerminal(rawID) {
        case .found(let found): meta = found
        case .failure(let text): return .failure(text)
        }
        guard watchList.watch(meta) else {
            return OrchestratorToolResult(
                text: "Already watching \"\(meta.displayTitle)\" (\(meta.id)). Use read_terminal for its latest messages."
            )
        }
        let header = "Now watching \"\(meta.displayTitle)\" (\(meta.id), \(status(of: meta))) — Lumi adds an activity "
            + "note when it finishes a turn, waits on a decision or fails."
        return OrchestratorToolResult(text: header + "\n\nSo far:\n" + (await catchUpSummary(of: meta)))
    }

    func unwatchTerminal(_ args: [String: Any]) -> OrchestratorToolResult {
        guard let rawID = args["terminal_id"] as? String, !rawID.isEmpty else {
            return .failure("terminal_id is required.")
        }
        let meta: TerminalMeta
        switch resolveTerminal(rawID) {
        case .found(let found): meta = found
        case .failure(let text): return .failure(text)
        }
        let text = watchList.unwatch(meta)
            ? "Stopped watching \"\(meta.displayTitle)\"; its updates no longer reach you."
            : "\"\(meta.displayTitle)\" was not being watched."
        return OrchestratorToolResult(text: text)
    }

    /// Oturumun o ana kadarki özeti; özetleyici yoksa ya da başarısızsa son
    /// asistan mesajının kırpılmış hâli.
    func catchUpSummary(of meta: TerminalMeta) async -> String {
        let messages: [ChatMessage]
        if let sessionID = meta.claudeSessionID {
            messages = await transcripts.recentClaudeMessages(sessionID: sessionID, cwd: meta.repoPath)
        } else {
            messages = []
        }
        guard messages.contains(where: { !$0.plainText.isEmpty }) else {
            return "(no conversation yet)"
        }
        let transcript = OrchestratorToolFormat.transcript(messages, limit: Self.catchUpMessageLimit)
        var reason = "no summarizer"
        if let summarizer {
            do {
                let digest = try await summarizer.summarizeSession(transcript: transcript, terminalTitle: meta.displayTitle)
                return digest.summary + (digest.needsUser ? "\n(It is waiting on the user.)" : "")
            } catch {
                // Özet olmasa da son söz işe yarar — sebebiyle birlikte yedeğe düşer.
                reason = (error as? LumiError)?.errorDescription ?? error.localizedDescription
            }
        }
        let last = messages.last { $0.role == .assistant && !$0.plainText.isEmpty }?.plainText ?? ""
        return "Summary unavailable (\(reason)); its last message: "
            + OrchestratorToolFormat.truncated(last, to: TerminalDigestCoordinator.fallbackSummaryLimit)
    }
}
