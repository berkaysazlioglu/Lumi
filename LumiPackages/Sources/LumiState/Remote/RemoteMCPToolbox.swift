import Foundation
import LumiKit

/// `RemoteMCPTools`'un yürütücüsü (karar 143, Faz 5): Claude terminalinin araç
/// çağrılarını controller servisine çevirir. Onay kapısı Claude Code'un kendi
/// araç izni sorusudur; Lumi ayrıca sormaz.
@MainActor
public final class RemoteMCPToolbox: OrchestratorToolHandling {
    static let defaultMessageLimit = 20
    static let defaultScreenLines = 80
    static let maxLimit = 200
    static let minimumIdPrefix = 6
    static let connectTimeout: Duration = .seconds(15)

    private let controller: any RemoteControllerServicing

    public init(controller: any RemoteControllerServicing) {
        self.controller = controller
    }

    public func call(name: String, arguments: Data) async -> OrchestratorToolResult {
        let args = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
        do {
            switch name {
            case RemoteMCPTools.listHubs: return listHubs()
            case RemoteMCPTools.connectHub: return try await connectHub(args)
            case RemoteMCPTools.listTerminals: return try listTerminals(args)
            case RemoteMCPTools.readTerminal: return try await readTerminal(args)
            case RemoteMCPTools.sendToTerminal: return try await sendToTerminal(args)
            case RemoteMCPTools.startTerminal: return try await startTerminal(args)
            case RemoteMCPTools.closeTerminal: return try await closeTerminal(args)
            default: return .failure("Unknown tool \(name).")
            }
        } catch let failure as ToolFailure {
            return .failure(failure.message)
        } catch {
            return .failure(RemoteControllerStore.describe(error))
        }
    }

    // MARK: - Araçlar

    private func listHubs() -> OrchestratorToolResult {
        guard controller.directoryState == .connected || !controller.hubs.isEmpty else {
            return .failure("This Mac is not on a Lumi network (Lumi ▸ Remote ▸ Network), or the relay is unreachable.")
        }
        let hubs = controller.hubs.map { hub -> [String: Any] in
            ["name": hub.name, "id": hub.id, "online": hub.isOnline, "connection": Self.describe(controller.linkState(hub.id))]
        }
        return OrchestratorToolResult(text: Self.json(["hubs": hubs]))
    }

    private func connectHub(_ args: [String: Any]) async throws -> OrchestratorToolResult {
        let hub = try resolveHub(args)
        if controller.linkState(hub.id) == .connected { return OrchestratorToolResult(text: "Already connected to \(hub.name).") }
        let password = (args["password"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        await controller.connect(hubId: hub.id, password: password, remember: false)
        let deadline = ContinuousClock.now + Self.connectTimeout
        while ContinuousClock.now < deadline {
            switch controller.linkState(hub.id) {
            case .connected:
                return OrchestratorToolResult(text: "Connected to \(hub.name).")
            case .rejected(let reason):
                if reason == "password_required" {
                    return .failure("password required: ask the user for \(hub.name)'s Lumi hub password.")
                }
                return .failure(RemoteControllerStore.describeRejection(reason))
            case .waitingForHub:
                return .failure("\(hub.name) is offline.")
            case .connecting, .disconnected:
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return .failure("Timed out connecting to \(hub.name).")
    }

    private func listTerminals(_ args: [String: Any]) throws -> OrchestratorToolResult {
        let hub = try connectedHub(args)
        let snapshot = controller.snapshot(hub.id) ?? RemoteHubSnapshot()
        var projects: [[String: Any]] = []
        for project in snapshot.projects {
            var checkouts: [[String: Any]] = []
            for checkout in project.checkouts {
                var row: [String: Any] = ["title": checkout.title, "path": checkout.path,
                                          "terminals": checkout.agentIds.compactMap { terminalRow($0, in: snapshot) }]
                if let branch = checkout.branch { row["branch"] = branch }
                checkouts.append(row)
            }
            projects.append(["name": project.name, "checkouts": checkouts])
        }
        let others = snapshot.others.map { group -> [String: Any] in
            ["directory": group.path, "terminals": group.agentIds.compactMap { terminalRow($0, in: snapshot) }]
        }
        return OrchestratorToolResult(text: Self.json(["hub": hub.name, "projects": projects, "other": others]))
    }

    private func readTerminal(_ args: [String: Any]) async throws -> OrchestratorToolResult {
        let hub = try connectedHub(args)
        let session = try resolveTerminal(args, hub: hub)
        let header = "\(hub.name) / \(session.repoName) / \(Self.title(session)) — \(Self.status(session))"
        switch try await controller.readTerminal(hubId: hub.id, sessionId: session.id) {
        case .transcript(let messages):
            let limit = Self.limit(args["limit"], default: Self.defaultMessageLimit)
            return OrchestratorToolResult(text: header + "\n\n" + RemoteMCPFormat.transcript(messages, limit: limit))
        case .screen(let text):
            let limit = Self.limit(args["limit"], default: Self.defaultScreenLines)
            let tail = RemoteMCPFormat.screenTail(text, lines: limit)
            return OrchestratorToolResult(text: header + "\n\nLast screen lines:\n" + (tail.isEmpty ? "(screen is empty)" : tail))
        }
    }

    private func sendToTerminal(_ args: [String: Any]) async throws -> OrchestratorToolResult {
        let hub = try connectedHub(args)
        let session = try resolveTerminal(args, hub: hub)
        guard let text = args["text"] as? String, !text.isEmpty else { throw ToolFailure("text is required.") }
        let submit = args["submit"] as? Bool ?? true
        try await controller.sendText(hubId: hub.id, sessionId: session.id, text: text, submit: submit)
        return OrchestratorToolResult(text: "Sent to \(Self.title(session)) on \(hub.name)\(submit ? " and pressed Enter" : "").")
    }

    private func startTerminal(_ args: [String: Any]) async throws -> OrchestratorToolResult {
        let hub = try connectedHub(args)
        guard let path = args["checkout_path"] as? String, !path.isEmpty else { throw ToolFailure("checkout_path is required.") }
        let known = (controller.snapshot(hub.id)?.projects ?? []).flatMap(\.checkouts).map(\.path)
        guard known.contains(path) else {
            throw ToolFailure("\(path) is not a checkout on \(hub.name); use a path from remote_list_terminals.")
        }
        let kind: RemoteSessionKind
        switch args["kind"] as? String ?? "claude" {
        case "shell":
            kind = .shell
        case "claude":
            let model = try (args["model"] as? String).map { raw in
                guard let alias = ClaudeModelAlias(rawValue: raw) else { throw ToolFailure("Unknown model \(raw).") }
                return alias
            }
            kind = .claude(model: model)
        case let other:
            throw ToolFailure("Unknown kind \(other); use claude or shell.")
        }
        let prompt = kind == .shell ? "" : (args["prompt"] as? String ?? "")
        let id = try await controller.startSession(hubId: hub.id, checkoutPath: path, kind: kind, prompt: prompt)
        return OrchestratorToolResult(text: id.map { "Started terminal \($0) on \(hub.name)." } ?? "Started a terminal on \(hub.name).")
    }

    private func closeTerminal(_ args: [String: Any]) async throws -> OrchestratorToolResult {
        let hub = try connectedHub(args)
        let session = try resolveTerminal(args, hub: hub)
        try await controller.closeSession(hubId: hub.id, sessionId: session.id)
        return OrchestratorToolResult(text: "Closed \(Self.title(session)) on \(hub.name).")
    }

    // MARK: - Çözümleme

    struct ToolFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// Ad (büyük/küçük harf duyarsız) ya da kimlik.
    func resolveHub(_ args: [String: Any]) throws -> RemoteHubInfo {
        guard let raw = (args["hub"] as? String)?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            throw ToolFailure("hub is required; see remote_list_hubs.")
        }
        if let hub = controller.hubs.first(where: { $0.id == raw }) { return hub }
        let matches = controller.hubs.filter { $0.name.caseInsensitiveCompare(raw) == .orderedSame }
        guard matches.count == 1, let hub = matches.first else {
            throw ToolFailure(matches.isEmpty ? "No hub named \(raw); see remote_list_hubs." : "Several hubs are named \(raw); use the id.")
        }
        return hub
    }

    private func connectedHub(_ args: [String: Any]) throws -> RemoteHubInfo {
        let hub = try resolveHub(args)
        guard controller.linkState(hub.id) == .connected else {
            throw ToolFailure("Not connected to \(hub.name); call remote_connect_hub first.")
        }
        return hub
    }

    /// Tam kimlik ya da en az 6 karakterlik tekil önek.
    func resolveTerminal(_ args: [String: Any], hub: RemoteHubInfo) throws -> RemoteSessionInfo {
        guard let raw = (args["terminal_id"] as? String)?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            throw ToolFailure("terminal_id is required; see remote_list_terminals.")
        }
        let sessions = controller.snapshot(hub.id)?.sessions ?? []
        if let exact = sessions.first(where: { $0.id.lowercased() == raw }) { return exact }
        guard raw.count >= Self.minimumIdPrefix else { throw ToolFailure("Use at least \(Self.minimumIdPrefix) characters of the terminal id.") }
        let matches = sessions.filter { $0.id.lowercased().hasPrefix(raw) }
        guard matches.count == 1, let session = matches.first else {
            throw ToolFailure(matches.isEmpty ? "No terminal \(raw) on \(hub.name)." : "\(raw) matches several terminals; use more characters.")
        }
        return session
    }

    // MARK: - Biçim

    private func terminalRow(_ id: String, in snapshot: RemoteHubSnapshot) -> [String: Any]? {
        guard let session = snapshot.session(id) else { return nil }
        return ["id": session.id, "title": Self.title(session),
                "agent": session.provider?.rawValue ?? "shell", "status": Self.status(session)]
    }

    static func title(_ session: RemoteSessionInfo) -> String {
        if let title = session.title, !title.isEmpty { return title }
        return session.provider?.rawValue.capitalized ?? "Shell"
    }

    static func status(_ session: RemoteSessionInfo) -> String {
        switch AgentActivityState(status: TerminalStatus(rawValue: session.status) ?? .idle,
                                  isAwaitingDecision: session.awaitingDecision) {
        case .running: "running"
        case .awaitingDecision: "awaiting-decision"
        case .done: "done"
        case .failed: "error"
        case .idle: "idle"
        }
    }

    static func describe(_ state: RemoteHubLinkState) -> String {
        switch state {
        case .connected: "connected"
        case .connecting: "connecting"
        case .disconnected: "not connected"
        case .waitingForHub: "waiting for the hub"
        case .rejected(let reason): "refused (\(reason))"
        }
    }

    static func limit(_ raw: Any?, default value: Int) -> Int {
        min(max((raw as? NSNumber)?.intValue ?? value, 1), maxLimit)
    }

    static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

/// Okuma çıktısının model dili — orchestrator'ın `read_terminal` biçimiyle aynı.
enum RemoteMCPFormat {
    static func transcript(_ messages: [ChatMessage], limit: Int) -> String {
        OrchestratorToolFormat.transcript(messages, limit: limit)
    }

    static func screenTail(_ text: String, lines: Int) -> String {
        var rows = text.components(separatedBy: "\n").map { line in
            String(line.reversed().drop(while: \.isWhitespace).reversed())
        }
        while let last = rows.last, last.isEmpty { rows.removeLast() }
        return rows.suffix(lines).joined(separator: "\n")
    }
}
