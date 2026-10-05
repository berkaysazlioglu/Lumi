import Foundation
import LumiKit

/// Orchestrator araçlarının yürütücüsü (karar 114 Faz 2) — MCP sunucusunun
/// `tools/call` istekleri buraya düşer. Store'ların CANLI durumunu okur:
/// Projects paneliyle aynı ağaç (`ProjectTree`), terminal listesiyle aynı
/// durumlar. Yazma araçları (Faz 3, `OrchestratorToolbox+Actions`) kullanıcı
/// onayı olmadan hiçbir şeye dokunmaz.
///
/// Orchestrator yalnız Claude Code terminalleriyle çalışır: listelerde Codex
/// ve düz shell terminalleri görünmez, kimlikleri verilirse açıkça reddedilir.
@MainActor
public final class OrchestratorToolbox: OrchestratorToolHandling {
    let terminals: TerminalListStore
    let workspaces: ProjectWorkspaceStore
    let repos: RepoStore
    let transcripts: any TerminalTranscriptReading
    /// Terminal ekranının düz metni (scrollback + görünür satırlar).
    let screenText: @MainActor (TerminalID) -> String
    /// Faz 3: yazma eylemlerinin onay kapısı, meşgul ajan için kuyruk ve
    /// Claude'un ilk-açılış güven menüsünü atlatma.
    let approvals: OrchestratorApprovals
    let promptQueue: PromptQueueStore?
    let trust: (any ClaudeWorkspaceTrusting)?
    /// Faz 5: `ask_project`'in salt-okunur arka plan ajanı.
    let projectAsker: (any ProjectQuestionAnswering)?
    /// İzlenen terminaller ve sonradan izlemeye alınanın oturum özeti.
    public let watchList: OrchestratorWatchList
    let summarizer: (any TerminalDigestSummarizing)?
    let now: @MainActor () -> Date

    public init(
        terminals: TerminalListStore,
        workspaces: ProjectWorkspaceStore,
        repos: RepoStore,
        transcripts: any TerminalTranscriptReading,
        screenText: @escaping @MainActor (TerminalID) -> String,
        approvals: OrchestratorApprovals = OrchestratorApprovals(),
        promptQueue: PromptQueueStore? = nil,
        trust: (any ClaudeWorkspaceTrusting)? = nil,
        projectAsker: (any ProjectQuestionAnswering)? = nil,
        watchList: OrchestratorWatchList = OrchestratorWatchList(),
        summarizer: (any TerminalDigestSummarizing)? = nil,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.terminals = terminals
        self.workspaces = workspaces
        self.repos = repos
        self.transcripts = transcripts
        self.screenText = screenText
        self.approvals = approvals
        self.promptQueue = promptQueue
        self.trust = trust
        self.projectAsker = projectAsker
        self.watchList = watchList
        self.summarizer = summarizer
        self.now = now
    }

    public func call(name: String, arguments: Data) async -> OrchestratorToolResult {
        let args = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any] ?? [:]
        switch name {
        case OrchestratorTools.listProjects:
            return listProjects()
        case OrchestratorTools.listTerminals:
            return listTerminals(query: args["query"] as? String)
        case OrchestratorTools.readTerminal:
            return await readTerminal(args)
        case OrchestratorTools.sendToTerminal:
            return await sendToTerminal(args)
        case OrchestratorTools.startTerminal:
            return await startTerminal(args)
        case OrchestratorTools.askProject:
            return await askProject(args)
        case OrchestratorTools.watchTerminal:
            return await watchTerminal(args)
        case OrchestratorTools.unwatchTerminal:
            return unwatchTerminal(args)
        default:
            return .failure("Unknown tool: \(name)")
        }
    }

    // MARK: - list_projects

    private func listProjects() -> OrchestratorToolResult {
        let tree = projectTree()
        guard !tree.isEmpty else {
            return OrchestratorToolResult(text: "No projects in Lumi's Projects panel yet.")
        }
        let projects: [[String: Any]] = tree.map { project in
            [
                "name": project.name,
                "path": project.path,
                "checkouts": project.checkouts.map { checkout -> [String: Any] in
                    var dict: [String: Any] = [
                        "title": checkout.title,
                        "kind": checkout.kind.rawValue,
                        "path": checkout.path,
                        "terminals": checkout.terminalIDs.compactMap(terminals.meta(for:))
                            .filter(Self.isClaude).map(terminalSummary),
                    ]
                    if let branch = checkout.branch { dict["branch"] = branch }
                    return dict
                },
            ]
        }
        return OrchestratorToolResult(text: OrchestratorToolFormat.json(["projects": projects]))
    }

    // MARK: - list_terminals

    private func listTerminals(query: String?) -> OrchestratorToolResult {
        let locations = checkoutLocations()
        let filter = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let rows: [[String: Any]] = terminals.terminals
            .filter(Self.isClaude)
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
            .compactMap { meta in
                let location = locations[meta.repoPath] ?? fallbackLocation(for: meta.repoPath)
                let row = terminalRow(meta, location: location)
                guard filter.isEmpty || Self.haystack(meta, location: location).contains(filter) else { return nil }
                return row
            }
        guard !rows.isEmpty else {
            let text = filter.isEmpty ? "No Claude terminals are open in Lumi." : "No Claude terminal matches \"\(filter)\"."
            return OrchestratorToolResult(text: text)
        }
        return OrchestratorToolResult(text: OrchestratorToolFormat.json(["terminals": rows]))
    }

    // MARK: - read_terminal

    private func readTerminal(_ args: [String: Any]) async -> OrchestratorToolResult {
        guard let rawID = args["terminal_id"] as? String, !rawID.isEmpty else {
            return .failure("terminal_id is required.")
        }
        let meta: TerminalMeta
        switch resolveTerminal(rawID) {
        case .found(let found): meta = found
        case .failure(let message): return .failure(message)
        }
        let limit = Self.clampedLimit(args["limit"])
        let header = OrchestratorToolFormat.header(for: meta, status: status(of: meta))

        if let sessionID = meta.claudeSessionID {
            let messages = await transcripts.recentClaudeMessages(sessionID: sessionID, cwd: meta.repoPath)
            if !messages.isEmpty {
                return OrchestratorToolResult(text: header + "\n\n" + OrchestratorToolFormat.transcript(messages, limit: limit))
            }
        }
        let screen = OrchestratorToolFormat.screenTail(screenText(meta.id))
        let body = screen.isEmpty ? "(screen is empty)" : screen
        return OrchestratorToolResult(text: header + "\n\nLast screen lines:\n" + body)
    }

    enum Resolution {
        case found(TerminalMeta)
        case failure(String)
    }

    /// Tam UUID ya da en az 6 karakterlik TEKİL önek (büyük/küçük harf
    /// duyarsız). Claude olmayan terminal bulunsa da reddedilir.
    func resolveTerminal(_ raw: String) -> Resolution {
        switch resolveAnyTerminal(raw) {
        case .found(let meta) where !Self.isClaude(meta):
            return .failure("\"\(meta.displayTitle)\" is not a Claude Code terminal; the orchestrator only works with Claude terminals.")
        case let other:
            return other
        }
    }

    private func resolveAnyTerminal(_ raw: String) -> Resolution {
        let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = terminals.terminals
        if let exact = all.first(where: { $0.id.description.lowercased() == needle }) {
            return .found(exact)
        }
        guard needle.count >= Self.minimumPrefix else {
            return .failure("Unknown terminal id \"\(raw)\". Use an id from list_terminals.")
        }
        let matches = all.filter { $0.id.description.lowercased().hasPrefix(needle) }
        switch matches.count {
        case 1: return .found(matches[0])
        case 0: return .failure("Unknown terminal id \"\(raw)\". Use an id from list_terminals.")
        default: return .failure("Terminal id prefix \"\(raw)\" is ambiguous; use the full id.")
        }
    }

    static let minimumPrefix = 6

    static func isClaude(_ meta: TerminalMeta) -> Bool { meta.provider == .claude }

    static func clampedLimit(_ raw: Any?) -> Int {
        let value = (raw as? NSNumber)?.intValue ?? OrchestratorTools.defaultReadLimit
        return min(max(value, 1), OrchestratorTools.maxReadLimit)
    }

    // MARK: - Ortak

    struct Location {
        let project: String
        let checkout: String?
        let branch: String?
    }

    func projectTree() -> [ProjectTreeNode] {
        ProjectTree.build(
            favoritePaths: workspaces.sidebarProjectPaths,
            repos: repos.repos,
            workspaces: workspaces.records,
            terminals: terminals.terminals
        )
    }

    func checkoutLocations() -> [String: Location] {
        var locations: [String: Location] = [:]
        for project in projectTree() {
            for checkout in project.checkouts {
                locations[checkout.path] = Location(project: project.name, checkout: checkout.title, branch: checkout.branch)
            }
        }
        return locations
    }

    /// Bir checkout yolu (Projects ağacından) ya da bilinen bir repo kökü;
    /// başka yol nil — araçlar rastgele dizinlere uzanmaz.
    func resolveCheckout(_ path: String) -> Location? {
        checkoutLocations()[path] ?? repos.repo(at: path).map { _ in fallbackLocation(for: path) }
    }

    /// Projects panelinde olmayan bir yolda koşan terminal (ör. favoriden çıkarılmış proje).
    func fallbackLocation(for path: String) -> Location {
        Location(project: repos.repo(at: path)?.name ?? (path as NSString).lastPathComponent, checkout: nil, branch: nil)
    }

    func status(of meta: TerminalMeta) -> String {
        OrchestratorToolFormat.status(meta.status, isAwaitingDecision: terminals.awaitingDecisionIDs.contains(meta.id))
    }

    private func terminalSummary(_ meta: TerminalMeta) -> [String: Any] {
        [
            "id": meta.id.description,
            "title": meta.displayTitle,
            "status": status(of: meta),
            "watched": watchList.isWatched(meta),
            "lastActivity": OrchestratorToolFormat.ago(meta.lastActivityAt, now: now()),
        ]
    }

    private func terminalRow(_ meta: TerminalMeta, location: Location) -> [String: Any] {
        var row = terminalSummary(meta)
        row["project"] = location.project
        row["path"] = meta.repoPath
        if let checkout = location.checkout { row["checkout"] = checkout }
        if let branch = location.branch { row["branch"] = branch }
        if terminals.isMinimized(meta.id) { row["minimized"] = true }
        if terminals.activeTerminalID == meta.id { row["focused"] = true }
        return row
    }

    private static func haystack(_ meta: TerminalMeta, location: Location) -> String {
        [meta.displayTitle, meta.repoPath, location.project, location.checkout ?? "", location.branch ?? ""]
            .joined(separator: " ")
            .lowercased()
    }
}
