import Foundation
import LumiKit

/// POSIX tek-tırnak quoting: ' → '\'' .
func shellQuoted(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Telefona dönen `command_result` gövdesi.
///
/// Sonuç doğrudan `[String: Any]` olarak dönmez: sözlük `Sendable` değildir ve
/// main actor'da üretilen bir değer `RelayConnection` actor'üne gönderilemez
/// (Swift 6 `sending` kuralı — release derlemesinde hata). Bu yüzden komut
/// sonucu `Sendable` bir değerdir; sözlüğe çeviri gönderim noktasında yapılır.
struct CommandResult: Sendable {
    let commandId: String?
    let ok: Bool
    var error: String?
    var sessionId: String?
    var branches: [String]?

    static func ok(_ commandId: String?, sessionId: String? = nil,
                   branches: [String]? = nil) -> CommandResult {
        CommandResult(commandId: commandId, ok: true, sessionId: sessionId, branches: branches)
    }

    static func failure(_ commandId: String?, _ error: String) -> CommandResult {
        CommandResult(commandId: commandId, ok: false, error: error)
    }

    /// Tel üzerindeki JSON gövdesi: {commandId, ok, error?, sessionId?, branches?}.
    var payload: [String: Any] {
        var payload: [String: Any] = ["commandId": commandId ?? NSNull(), "ok": ok]
        if let error { payload["error"] = error }
        if let sessionId { payload["sessionId"] = sessionId }
        if let branches { payload["branches"] = branches }
        return payload
    }
}

/// Telefondan gelen komutları uygular (spec §4.2 RemoteCommandHandler).
/// Cevap her zaman command_result payload'ıdır: {commandId, ok, error?}.
@MainActor
final class RemoteCommandHandler {
    private let terminal: any TerminalServicing
    private let trust: any ClaudeWorkspaceTrusting
    private let chatSessions: any ChatSessionServicing
    private let repos: any RepoServicing
    private let workspaces: any WorkspaceServicing
    private let config: any ConfigServicing

    init(terminal: any TerminalServicing, trust: any ClaudeWorkspaceTrusting,
         chatSessions: any ChatSessionServicing = NoopChatSessionService(),
         repos: any RepoServicing = NoopRepoServicing(),
         workspaces: any WorkspaceServicing = NoopWorkspaceServicing(),
         config: any ConfigServicing) {
        self.terminal = terminal
        self.trust = trust
        self.chatSessions = chatSessions
        self.repos = repos
        self.workspaces = workspaces
        self.config = config
    }

    func handle(_ payload: [String: Any]) async -> CommandResult {
        let commandId = payload["commandId"] as? String
        switch payload["action"] as? String {
        case "send_text":
            return result(commandId, run: {
                let id = try self.session(from: payload)
                let text = payload["text"] as? String ?? ""
                try self.terminal.write(id: id, text: text + "\r")
            })
        case "press_key":
            guard let sequence = keySequence(for: payload["key"] as? String ?? "") else {
                return .failure(commandId, "unknown_key")
            }
            return result(commandId, run: {
                let id = try self.session(from: payload)
                try self.terminal.write(id: id, text: sequence)
            })
        case "delete_session":
            // Chat oturumu mu? Öyleyse chatSessions üzerinden kapat — chat oturumları
            // terminal PTY kaydında YOK, `session(from:)` onları bulamaz ve
            // session_not_found döndürür ("chatte silemiyorum" regresyonu).
            let rawId = payload["sessionId"] as? String ?? ""
            if await chatSessions.list().contains(where: { $0.id == rawId }) {
                await chatSessions.close(id: rawId)
                return .ok(commandId)
            }
            return result(commandId, run: {
                let id = try self.session(from: payload)
                try self.terminal.kill(id: id)
            })
        case "start_session":
            return await startSession(payload, commandId: commandId)
        case "set_model":
            let model = payload["model"] as? String ?? ""
            guard Self.allowedModels.contains(model) else {
                return .failure(commandId, "unknown_model")
            }
            return result(commandId, run: {
                let id = try self.session(from: payload)
                try self.terminal.write(id: id, text: "/model \(model)\r")
            })
        case "list_branches":
            return await listBranches(payload, commandId: commandId)
        case "add_project":
            return await addProject(payload, commandId: commandId)
        default:
            return .failure(commandId, "unknown_action")
        }
    }

    private func startSession(_ payload: [String: Any], commandId: String?) async -> CommandResult {
        let repoPath = payload["repoPath"] as? String ?? ""
        let prompt = payload["prompt"] as? String ?? ""
        let kind = payload["kind"] as? String

        if kind == "chat" {
            // Karar 80: telefon-başlatılan chat, başsız stream-json alt-süreci DEĞİL,
            // masaüstü grid'de de görünen bir claude TERMİNALİ olarak açılır — böylece
            // Mac'te takip edilebilir ve telefon onu transcript-tail chat ile izler
            // (karar 79 birleşimi; Mac-başlatılan claude terminalleriyle simetrik).
            // branchMode != "current" ise önce workspace/worktree oluşturulur.
            var chatRepoPath = repoPath
            let mode = payload["branchMode"] as? String
            if let mode, mode != "current" {
                guard let repo = await repoFor(repoPath) else {
                    return .failure(commandId, "unknown_repo")
                }
                let branchMode = WorkspaceBranchMode(rawValue: mode) ?? .new
                let branchName = payload["branchName"] as? String
                let wsName = (payload["workspaceName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? branchName ?? "workspace"
                let request = WorkspaceCreateRequest(
                    project: repo, name: wsName, branchName: branchName,
                    branchMode: branchMode, baseBranch: payload["baseBranch"] as? String,
                    copyLibrary: false, knownProjectPaths: await repos.repos().map(\.path))
                do {
                    let created = try await workspaces.create(request)
                    chatRepoPath = created.workspace.path
                } catch {
                    return .failure(commandId, "\(error)")
                }
            }
            // İlk-açılış güven menüsünde takılmasın diye spawn'dan ÖNCE güvenli işaretle.
            trust.markTrusted(repoPath: chatRepoPath)
            let command = prompt.isEmpty ? "claude" : "claude " + shellQuoted(prompt)
            do {
                // sessionId = spawn edilen terminalin id'si → telefon subscribeChat için.
                let meta = try terminal.spawn(repoPath: chatRepoPath, task: nil, command: command)
                return .ok(commandId, sessionId: meta.id.description)
            } catch {
                return .failure(commandId, "\(error)")
            }
        }

        // Terminal oturumu (varsayılan): PTY spawn.
        do {
            // Remote'tan başlatılan claude, ilk-açılış güven menüsünde takılmasın:
            // çalışma alanını spawn'dan ÖNCE güvenli işaretle (telefon chat modu bu
            // menüyü göremez → transcript yazılmaz → chat "yükleniyor"da kalır).
            trust.markTrusted(repoPath: repoPath)
            let command = prompt.isEmpty ? "claude" : "claude " + shellQuoted(prompt)
            _ = try terminal.spawn(repoPath: repoPath, task: nil, command: command)
            return .ok(commandId)
        } catch {
            return .failure(commandId, "\(error)")
        }
    }

    private func repoFor(_ path: String) async -> Repo? {
        await repos.repos().first { $0.path == path }
    }

    private func listBranches(_ payload: [String: Any], commandId: String?) async -> CommandResult {
        let repoPath = payload["repoPath"] as? String ?? ""
        guard let repo = await repoFor(repoPath) else {
            return .failure(commandId, "unknown_repo")
        }
        do {
            let branches = try await workspaces.branches(project: repo, limit: 100)
            return .ok(commandId, branches: branches.map(\.name))
        } catch {
            return .failure(commandId, "\(error)")
        }
    }

    private func addProject(_ payload: [String: Any], commandId: String?) async -> CommandResult {
        let path = payload["path"] as? String ?? ""
        guard !path.isEmpty, await repos.repos().contains(where: { $0.path == path }) else {
            return .failure(commandId, "unknown_repo")
        }
        do {
            try await config.updateConfig { c in
                if !c.sidebarProjectPaths.contains(path) { c.sidebarProjectPaths.append(path) }
            }
            return .ok(commandId)
        } catch {
            return .failure(commandId, "\(error)")
        }
    }

    private func session(from payload: [String: Any]) throws -> TerminalID {
        guard let raw = payload["sessionId"] as? String,
              let uuid = UUID(uuidString: raw),
              terminal.terminals.contains(where: { $0.id.raw == uuid })
        else { throw CommandError.sessionNotFound }
        return TerminalID(raw: uuid)
    }

    private func result(_ commandId: String?, run: () throws -> Void) -> CommandResult {
        do {
            try run()
            return .ok(commandId)
        } catch CommandError.sessionNotFound {
            return .failure(commandId, "session_not_found")
        } catch {
            return .failure(commandId, "\(error)")
        }
    }

    private static let allowedModels: Set<String> = ["opus", "sonnet", "haiku", "default"]

    private enum CommandError: Error { case sessionNotFound }
}
