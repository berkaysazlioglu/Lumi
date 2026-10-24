import Foundation
import LumiKit

/// Task → ajan (Tasks planı: "Task'i ajana vermek").
///
/// `Start` bağlantıyı kurar, isteğe göre task'i In Progress'e çeker ve bana
/// atar, sonra koşucunun olaylarını bağlantıya yansıtır. Ajan işi teslim
/// edince (`submitted`) task hemen In Review'a gider — erteleme beklemeden.
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
        let events = agents.start(request)
        agentRuns[key]?.cancel()
        agentRuns[key] = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else { return }
                await self.handle(event, for: key)
            }
        }
    }

    /// Ajanı durdurur (önizlemede akışı keser; Faz 3'te terminali kapatmayı sorar).
    public func stopAgent(_ key: TaskKey) {
        agentRuns.removeValue(forKey: key)?.cancel()
        guard agentLinks[key]?.state.isActive == true else { return }
        agentLinks[key]?.state = .exited
    }

    /// Bağlantıyı karttan kaldırır (ajan bittikten sonra).
    public func dismissAgent(_ key: TaskKey) {
        stopAgent(key)
        agentLinks[key] = nil
    }

    /// Ajan teslim etmeden durduysa kullanıcının elle In Review'a taşıması.
    public func moveToReview(_ key: TaskKey) {
        move(key, to: .inReview)
    }

    func handle(_ event: TaskAgentEvent, for key: TaskKey) async {
        guard agentLinks[key] != nil else { return }
        switch event {
        case .started(let terminalID):
            agentLinks[key]?.terminalID = terminalID
        case .state(let state):
            agentLinks[key]?.state = state
            if case .submitted = state {
                move(key, to: .inReview)
                await flush(key)
            }
        }
    }
}
