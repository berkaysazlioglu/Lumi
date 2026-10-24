import Foundation
import LumiKit

/// Task → ajan (karar 137).
///
/// `Start` bağlantıyı kurar, isteğe göre task'i In Progress'e çeker ve bana
/// atar, sonra koşucunun olaylarını bağlantıya yansıtır. Ajan işi teslim
/// edince (`submitted`) task hemen In Review'a gider — erteleme beklemeden.
/// Gerçek ajanın bağlantısı (oturum kimliğiyle) `ui-state.json`'a yazılır;
/// Lumi yeniden açılınca resume edilen terminale yeniden bağlanır.
extension TasksStore {
    public var isAgentPreview: Bool { agents.isPreview }

    public func agentLink(for key: TaskKey) -> TaskAgentLink? {
        agentLinks[key]
    }

    public func beginStart(_ key: TaskKey) {
        guard entry(key) != nil, agentLinks[key]?.state.isActive != true else { return }
        startingTask = key
    }

    public func cancelStart() {
        startingTask = nil
    }

    /// Start sheet'inin proje eşleşmesi için Lumi projelerinin git origin'leri.
    public func origins(for projectPaths: [String]) async -> [String: String] {
        var result: [String: String] = [:]
        for path in projectPaths {
            if let origin = await remoteURL(path) { result[path] = origin }
        }
        return result
    }

    public func start(_ request: TaskAgentRequest, moveToInProgress: Bool, assignToMe: Bool) {
        let key = request.task
        guard let current = entry(key), agentLinks[key]?.state.isActive != true else { return }
        startingTask = nil
        agentLinks[key] = TaskAgentLink(task: key, agent: request.agent, checkout: request.checkout, startedAt: now())
        if moveToInProgress, current.item.status != .inProgress {
            move(key, to: .inProgress)
        }
        if assignToMe, let me = info(of: key.source)?.me, current.item.assignee?.id != me.id {
            assign(key, to: me)
        }
        consume(agents.start(request), for: key)
    }

    /// `get_task`'in metni — Start anındaki hâliyle.
    public func agentDetails(for key: TaskKey) -> String {
        guard let entry = entry(key) else { return key.id }
        return TaskAgentPrompt.details(for: entry.item, includeBody: info(of: key.source)?.canRead(.body) == true)
    }

    /// Bağlantıyı bırakır; terminal açık kalır (kapatmak kullanıcının işi).
    public func stopAgent(_ key: TaskKey) {
        agentRuns.removeValue(forKey: key)?.cancel()
        guard agentLinks[key]?.state.isActive == true else { return }
        agentLinks[key]?.state = .exited
        persistAgentLinks()
    }

    /// Bağlantıyı karttan kaldırır (ajan bittikten sonra).
    public func dismissAgent(_ key: TaskKey) {
        stopAgent(key)
        agentLinks[key] = nil
        persistAgentLinks()
    }

    /// Ajan teslim etmeden durduysa kullanıcının elle In Review'a taşıması.
    public func moveToReview(_ key: TaskKey) {
        move(key, to: .inReview)
    }

    // MARK: - Olaylar

    func consume(_ events: AsyncStream<TaskAgentEvent>, for key: TaskKey) {
        agentRuns[key]?.cancel()
        agentRuns[key] = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                await self.handle(event, for: key)
            }
            // Yeniden bağlanma terminali bulamadıysa kayıt bayattır.
            guard let self, let link = self.agentLinks[key], link.isReattached, link.terminalID == nil else { return }
            self.agentLinks[key] = nil
            self.persistAgentLinks()
        }
    }

    func handle(_ event: TaskAgentEvent, for key: TaskKey) async {
        guard agentLinks[key] != nil else { return }
        switch event {
        case .started(let terminalID, let sessionID):
            agentLinks[key]?.terminalID = terminalID
            agentLinks[key]?.sessionID = sessionID
            persistAgentLinks()
        case .checkout(let path):
            if let link = agentLinks[key] {
                agentLinks[key] = TaskAgentLink(
                    task: key, agent: link.agent, checkout: .existing(path: path), state: link.state,
                    startedAt: link.startedAt, terminalID: link.terminalID, sessionID: link.sessionID
                )
            }
        case .state(let state):
            // Teslimden sonra yalnız kapanış çipi değiştirir.
            if case .submitted = agentLinks[key]?.state, state != .exited { return }
            agentLinks[key]?.state = state
            if case .submitted = state {
                persistAgentLinks()
                move(key, to: .inReview)
                await flush(key)
            } else if state == .exited {
                persistAgentLinks()
            }
        case .failed(let message):
            agentLinks[key]?.state = .exited
            toasts.show(.error, title: "Couldn't start the agent for \(key.id)", message: message)
        }
    }

    // MARK: - Kalıcılık

    /// Yalnız gerçek terminali olan (oturum kimliği bilinen) ve hâlâ anlamlı
    /// bağlantılar yazılır; kapanan ajanın kaydı düşer.
    func persistAgentLinks() {
        let records = agentLinks.values.compactMap { link -> TaskAgentLinkRecord? in
            guard let sessionID = link.sessionID, link.state != .exited else { return nil }
            let checkout: String = switch link.checkout {
            case .existing(let path): path
            case .newWorkspace(let projectPath, _): projectPath
            }
            var summary: String?
            if case .submitted(let text) = link.state { summary = text }
            return TaskAgentLinkRecord(
                source: link.task.source, taskID: link.task.id, sessionID: sessionID, checkoutPath: checkout,
                model: link.agent.model, startedAt: link.startedAt, summary: summary
            )
        }
        .sorted { $0.startedAt < $1.startedAt }
        Task { [config] in await config.updateUIState { $0.taskLinks = records } }
    }

    /// Açılışta: kayıtlı bağlantıları resume edilmiş terminallere bağlar.
    /// Terminali bulunamayan kayıt (akış `started` demeden biter) düşer.
    func restoreAgentLinks() async {
        guard let records = await config.uiState().taskLinks, !records.isEmpty else { return }
        for record in records where agentLinks[record.key] == nil {
            agentLinks[record.key] = TaskAgentLink(
                task: record.key, agent: TaskAgentChoice(model: record.model),
                checkout: .existing(path: record.checkoutPath),
                state: record.summary.map { .submitted(summary: $0) } ?? .starting,
                startedAt: record.startedAt, sessionID: record.sessionID, isReattached: true
            )
            consume(agents.reattach(sessionID: record.sessionID, task: record.key), for: record.key)
        }
    }
}
