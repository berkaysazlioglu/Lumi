import Foundation
import LumiKit

/// Yazma araçları (karar 114 Faz 3, karar 123'ten beri onaysız): çağrıldıkları
/// an çalışırlar — Codex orchestrator'ı auto modda koşar ve doğru hedefi
/// seçmek talimatın işidir. Başarılı her eylemin hedefi izlemeye alınır:
/// cevabı Activity'ye ve monitor üzerinden orchestrator'a düşer.
extension OrchestratorToolbox {
    // MARK: - send_to_terminal

    /// Ajan hemen mi alır, yoksa turn bitince mi (prompt kuyruğu)?
    enum Delivery: Equatable {
        case now
        case queued
    }

    func delivery(for meta: TerminalMeta) -> Delivery {
        let isAwaiting = terminals.awaitingDecisionIDs.contains(meta.id)
        guard !isAwaiting, meta.status.isWaiting || meta.status == .idle else { return .queued }
        return .now
    }

    func sendToTerminal(_ args: [String: Any]) -> OrchestratorToolResult {
        guard let rawID = args["terminal_id"] as? String, !rawID.isEmpty else {
            return .failure("terminal_id is required.")
        }
        let message = (args["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !message.isEmpty else { return .failure("message is required.") }
        let meta: TerminalMeta
        switch resolveTerminal(rawID) {
        case .found(let found): meta = found
        case .failure(let text): return .failure(text)
        }
        switch delivery(for: meta) {
        case .now:
            guard terminals.submit(message, to: meta.id) else {
                return .failure("Writing to \"\(meta.displayTitle)\" failed.")
            }
            return OrchestratorToolResult(text: "Sent to \"\(meta.displayTitle)\" (\(meta.id))." + watchNote(meta))
        case .queued:
            guard let promptQueue else {
                return .failure("\"\(meta.displayTitle)\" is busy and no prompt queue is available; try again when it is waiting.")
            }
            promptQueue.enqueue(message, for: meta.id)
            let position = promptQueue.count(for: meta.id)
            let paused = promptQueue.isPaused(meta.id) ? " Its queue is paused, so it waits until the user resumes it." : ""
            return OrchestratorToolResult(
                text: "\"\(meta.displayTitle)\" is busy — queued at position \(position); it is sent when the agent finishes its current turn.\(paused)"
                    + watchNote(meta)
            )
        }
    }

    // MARK: - start_terminal

    func startTerminal(_ args: [String: Any]) -> OrchestratorToolResult {
        guard let rawPath = (args["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else {
            return .failure("path is required.")
        }
        guard let (path, location) = resolveCheckout(rawPath) else {
            return .failure("Unknown checkout path \"\(rawPath)\". Use a checkout path from list_projects.")
        }
        let prompt = (args["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // İlk prompt ilk-açılış güven menüsünde takılmasın (karar 89 ile aynı).
        trust?.markTrusted(repoPath: path)
        let launch = AgentProvider.claude.launchCommand
        let command = prompt.isEmpty ? launch : launch + " " + shellQuoted(prompt)
        guard let meta = terminals.spawn(in: path, command: command) else {
            return .failure("Lumi could not open a terminal in \(path).")
        }
        return OrchestratorToolResult(
            text: "Started Claude in \(location.project) at \(path) — terminal id \(meta.id)." + watchNote(meta)
        )
    }

    // MARK: - Ortak

    /// Eylemin hedefini izlemeye alır; yeni eklendiyse modele söyler.
    func watchNote(_ meta: TerminalMeta) -> String {
        watchList.watch(meta) ? " Lumi now watches it: its reply arrives as an activity note." : ""
    }

    /// proje · checkout · dal (Activity kartı ve bağlam notu — Faz 4).
    func location(of meta: TerminalMeta) -> String {
        let location = terminalLocations()[meta.repoPath] ?? fallbackLocation(for: meta.repoPath)
        return [location.project, location.checkout, location.branch].compactMap { $0 }.joined(separator: " · ")
    }

    /// Ajanın son sözü (Faz 4): transkriptteki son metinli asistan mesajı;
    /// transkript henüz yoksa ekranın son satırları. Hiçbiri yoksa nil.
    func lastAgentMessage(of meta: TerminalMeta) async -> String? {
        if let sessionID = meta.claudeSessionID {
            let messages = await transcripts.recentClaudeMessages(sessionID: sessionID, cwd: meta.repoPath)
            let lastText = messages.last { $0.role == .assistant && !$0.plainText.isEmpty }?.plainText
            if let lastText { return lastText }
        }
        let screen = OrchestratorToolFormat.screenTail(screenText(meta.id))
        return screen.isEmpty ? nil : screen
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
