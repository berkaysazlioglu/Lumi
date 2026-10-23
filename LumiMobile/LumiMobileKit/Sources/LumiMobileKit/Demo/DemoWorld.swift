import Foundation
import LumiWire

/// The fake Mac's mutable state: sessions, the projects tree, chats, live turns
/// and pending prompts. Pure value type — `DemoRelayClient` owns one and turns
/// its changes into relay frames.
struct DemoWorld: Sendable {
    private(set) var sessions: [SessionMeta]
    private(set) var projects: [ProjectNode]
    private(set) var others: [OtherGroupNode]
    private(set) var addable: [Repo]
    let looseLocations: [LooseLocation]
    private(set) var chats: [String: DemoChatBuilder]
    private(set) var turns: [String: ChatTurnStatus]
    private(set) var prompts: [String: [ChatPrompt]]
    private var newSessionCounter = 0

    init(nowMs: Double) {
        sessions = DemoData.sessions(nowMs: nowMs)
        projects = DemoData.projects
        others = DemoData.others
        addable = DemoData.addable
        looseLocations = DemoData.looseLocations
        chats = DemoTranscripts.seed(nowMs: nowMs)
        turns = [DemoIDs.tiles: DemoData.tilesTurn(nowMs: nowMs),
                 DemoIDs.rewards: DemoData.rewardsTurn(nowMs: nowMs)]
        prompts = [DemoIDs.rewards: [DemoData.rewardsPrompt]]
    }

    // MARK: Read

    var snapshot: ProjectsSnapshot {
        ProjectsSnapshot(projects: projects, others: others, addable: addable,
                         looseLocations: looseLocations, display: DemoData.display)
    }

    var repos: [Repo] { projects.map { Repo(name: $0.name, path: $0.path) } }

    func session(_ id: String) -> SessionMeta? { sessions.first { $0.id == id } }

    func messages(_ id: String) -> [ChatMessage] { chats[id]?.messages ?? [] }

    func turn(_ id: String) -> ChatTurnStatus { turns[id] ?? .idle }

    func pendingPrompts(_ id: String) -> [ChatPrompt] {
        (prompts[id] ?? []).filter { $0.state == .pending }
    }

    /// Working directory of a session (checkout or Other folder).
    func cwd(of id: String) -> String {
        for project in projects {
            if let checkout = project.checkouts.first(where: { $0.agentIds.contains(id) }) {
                return checkout.path
            }
        }
        return others.first { $0.agentIds.contains(id) }?.path ?? DemoPaths.home
    }

    // MARK: Sessions

    /// Opens a new empty Claude chat at `repoPath` (a checkout, a project root or
    /// any loose folder). A new/existing branch with a name creates a workspace.
    mutating func startSession(repoPath: String, branchMode: String?, branchName: String?,
                               workspaceName: String?, nowMs: Double) -> String? {
        guard !repoPath.isEmpty else { return nil }
        newSessionCounter += 1
        let id = "demo-new-\(newSessionCounter)"
        let repoName: String
        if let index = projects.firstIndex(where: { $0.path == repoPath || $0.checkouts.contains { $0.path == repoPath } }) {
            repoName = projects[index].name
            let workspace = Self.workspaceName(mode: branchMode, branch: branchName, name: workspaceName)
            projects[index] = projects[index].demoAdding(agent: id, at: repoPath, workspace: workspace,
                                                          branch: branchName)
        } else {
            repoName = URL(fileURLWithPath: repoPath).lastPathComponent
            addLoose(agent: id, at: repoPath)
        }
        sessions.append(DemoData.chat(id, repoName, "idle", nil, DemoData.sonnet, nowMs))
        chats[id] = DemoChatBuilder(prefix: id, startMs: Int(nowMs))
        return id
    }

    /// Removes a session everywhere; false if unknown.
    mutating func deleteSession(_ id: String) -> Bool {
        guard sessions.contains(where: { $0.id == id }) else { return false }
        sessions.removeAll { $0.id == id }
        projects = projects.map { $0.demoRemoving(agent: id) }
        others = others.compactMap { group in
            let ids = group.agentIds.filter { $0 != id }
            return ids.isEmpty ? nil : OtherGroupNode(path: group.path, label: group.label, agentIds: ids)
        }
        chats[id] = nil
        turns[id] = nil
        prompts[id] = nil
        return true
    }

    /// Moves an addable repo into the projects list; false if not addable.
    mutating func addProject(path: String) -> Bool {
        guard let repo = addable.first(where: { $0.path == path }) else { return false }
        addable.removeAll { $0.path == path }
        projects.append(ProjectNode(name: repo.name, path: repo.path, checkouts: [
            CheckoutNode(kind: "original", title: "main", branch: "main", scm: "git",
                         path: repo.path, agentIds: []),
        ]))
        return true
    }

    mutating func update(_ id: String, status: String? = nil, awaitingDecision: Bool? = nil,
                         model: String? = nil, nowMs: Double) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index] = sessions[index].demoUpdated(status: status, awaitingDecision: awaitingDecision,
                                                      lastActivityAt: nowMs, model: model)
    }

    // MARK: Chat

    /// Appends messages produced by `build`; returns only the new ones.
    mutating func appendChat(_ id: String, nowMs: Double,
                             _ build: (inout DemoChatBuilder) -> Void) -> [ChatMessage] {
        var builder = chats[id] ?? DemoChatBuilder(prefix: id, startMs: Int(nowMs))
        let before = builder.messages.count
        builder.advanceClock(to: Int(nowMs))
        build(&builder)
        chats[id] = builder
        return Array(builder.messages.dropFirst(before))
    }

    mutating func completeRunningTools(_ id: String) -> [ChatMessage] {
        chats[id]?.completeRunningTools() ?? []
    }

    mutating func setTurn(_ id: String, _ status: ChatTurnStatus) {
        turns[id] = status.working ? status : nil
    }

    /// Resolves a pending prompt; returns the resolved copy (nil if not pending).
    mutating func resolvePrompt(_ id: String, itemId: String, optionId: String?) -> ChatPrompt? {
        guard var list = prompts[id],
              let index = list.firstIndex(where: { $0.itemId == itemId && $0.state == .pending }) else { return nil }
        list[index].state = .resolved
        list[index].selectedOptionId = optionId
        list[index].revision += 1
        let resolved = list[index]
        prompts[id] = list.filter { $0.state == .pending }
        return resolved
    }

    // MARK: Helpers

    private static func workspaceName(mode: String?, branch: String?, name: String?) -> String? {
        guard mode == "new" || mode == "existing" else { return nil }
        if let name, !name.isEmpty { return name }
        guard let branch, !branch.isEmpty else { return nil }
        return branch.split(separator: "/").last.map(String.init)
    }

    private mutating func addLoose(agent id: String, at path: String) {
        if let index = others.firstIndex(where: { $0.path == path }) {
            let group = others[index]
            others[index] = OtherGroupNode(path: group.path, label: group.label, agentIds: group.agentIds + [id])
        } else {
            others.append(OtherGroupNode(path: path, label: DemoPaths.shortLabel(path), agentIds: [id]))
        }
    }
}
