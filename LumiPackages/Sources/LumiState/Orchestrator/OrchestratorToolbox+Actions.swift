import Foundation
import LumiKit

/// Yazma araçları (karar 103 Faz 3). İkisi de önce popup'ta onay ister; onay
/// gelene kadar hiçbir terminale dokunulmaz. Onaydan SONRA hedef yeniden
/// çözülür — bekleme sırasında terminal kapanmış ya da durumu değişmiş olabilir.
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

    func sendToTerminal(_ args: [String: Any]) async -> OrchestratorToolResult {
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
        guard meta.provider != nil else {
            return .failure("\"\(meta.displayTitle)\" is a plain shell, not an agent chat; only Claude/Codex terminals accept messages.")
        }

        let decision = await approvals.request(OrchestratorApprovalRequest(
            kind: .sendMessage,
            title: "Send to “\(meta.displayTitle)”",
            target: target(of: meta),
            body: message,
            note: delivery(for: meta) == .queued
                ? "The agent is busy — the message is queued and sent when it finishes its turn."
                : nil
        ))
        if let declined = Self.outcome(of: decision) { return declined }

        guard let current = terminals.meta(for: meta.id) else {
            return .failure("\"\(meta.displayTitle)\" was closed before the message could be sent.")
        }
        switch delivery(for: current) {
        case .now:
            guard terminals.submit(message, to: current.id) else {
                return .failure("Writing to \"\(current.displayTitle)\" failed.")
            }
            return OrchestratorToolResult(text: "Sent to \"\(current.displayTitle)\" (\(current.id)).")
        case .queued:
            guard let promptQueue else {
                return .failure("\"\(current.displayTitle)\" is busy and no prompt queue is available; try again when it is waiting.")
            }
            promptQueue.enqueue(message, for: current.id)
            let position = promptQueue.count(for: current.id)
            let paused = promptQueue.isPaused(current.id) ? " Its queue is paused, so it waits until the user resumes it." : ""
            return OrchestratorToolResult(
                text: "\"\(current.displayTitle)\" is busy — queued at position \(position); it is sent when the agent finishes its current turn.\(paused)"
            )
        }
    }

    // MARK: - start_terminal

    func startTerminal(_ args: [String: Any]) async -> OrchestratorToolResult {
        guard let path = (args["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return .failure("path is required.")
        }
        let rawProvider = (args["provider"] as? String)?.lowercased() ?? AgentProvider.claude.rawValue
        guard let provider = AgentProvider(rawValue: rawProvider) else {
            return .failure("provider must be \"claude\" or \"codex\".")
        }
        guard let location = checkoutLocations()[path] ?? repos.repo(at: path).map({ _ in fallbackLocation(for: path) }) else {
            return .failure("Unknown checkout path \"\(path)\". Use a checkout path from list_projects.")
        }
        let prompt = (args["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = provider == .claude ? "Claude" : "Codex"

        let decision = await approvals.request(OrchestratorApprovalRequest(
            kind: .startTerminal,
            title: "Start \(name)",
            target: [location.project, location.checkout, location.branch].compactMap { $0 }.joined(separator: " · ")
                + " — \(path)",
            body: prompt.isEmpty ? "(no first prompt)" : prompt
        ))
        if let declined = Self.outcome(of: decision) { return declined }

        // İlk prompt ilk-açılış güven menüsünde takılmasın (karar 89 ile aynı).
        if provider == .claude { trust?.markTrusted(repoPath: path) }
        let command = prompt.isEmpty ? provider.launchCommand : provider.launchCommand + " " + shellQuoted(prompt)
        guard let meta = terminals.spawn(in: path, command: command) else {
            return .failure("Lumi could not open a terminal in \(path).")
        }
        return OrchestratorToolResult(text: "Started \(name) in \(location.project) at \(path) — terminal id \(meta.id).")
    }

    // MARK: - Ortak

    /// Onaylanmadıysa modele dönecek sonuç; onaylandıysa nil.
    static func outcome(of decision: OrchestratorApprovals.Decision) -> OrchestratorToolResult? {
        switch decision {
        case .approved:
            return nil
        case .rejected:
            return .failure("The user declined this action; nothing was done. Do not retry unless they ask.")
        case .timedOut:
            return .failure("The user did not answer the approval in time; nothing was done.")
        }
    }

    /// proje · checkout · dal (Activity kartı ve bağlam notu — Faz 4).
    func location(of meta: TerminalMeta) -> String {
        let location = checkoutLocations()[meta.repoPath] ?? fallbackLocation(for: meta.repoPath)
        return [location.project, location.checkout, location.branch].compactMap { $0 }.joined(separator: " · ")
    }

    /// Ajanın son sözü (Faz 4): Claude'da transkriptteki son metinli asistan
    /// mesajı, diğerlerinde ekranın son satırları. Hiçbiri yoksa nil.
    func lastAgentMessage(of meta: TerminalMeta) async -> String? {
        if meta.provider == .claude, let sessionID = meta.claudeSessionID {
            let messages = await transcripts.recentClaudeMessages(sessionID: sessionID, cwd: meta.repoPath)
            let lastText = messages.last { $0.role == .assistant && !$0.plainText.isEmpty }?.plainText
            if let lastText { return lastText }
        }
        let screen = OrchestratorToolFormat.screenTail(screenText(meta.id))
        return screen.isEmpty ? nil : screen
    }

    /// Kartın hedef satırı: proje · checkout · dal · sağlayıcı · durum.
    func target(of meta: TerminalMeta) -> String {
        [location(of: meta), meta.provider?.rawValue ?? "shell", status(of: meta)].joined(separator: " · ")
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
