import Foundation
import LumiKit
import LumiState
import Observation

/// Telefondaki Tasks köprüsü (karar 137 mobil ek).
///
/// İki yön: `TasksStore` değiştikçe `tasks` anlık görüntüsünü yayınlar
/// (300 ms birleştirerek) ve telefondan gelen `task_*` komutlarını store'da
/// yürütür. Token'lar, adapter'lar, birleşik yazım ve ajan koşucusu Mac'te
/// kalır — telefon task sunucusuyla hiç konuşmaz.
@MainActor
final class RemoteTasksBridge: RemoteTasksHandling {
    struct ProjectLookup {
        /// Projects'teki projeler (telefonun da gördüğü liste).
        let projectPaths: @MainActor () -> [String]
        /// Proje git deposu mu (yeni workspace yalnız git'te).
        let isGit: @MainActor (String) -> Bool
    }

    private let store: TasksStore
    private let projects: ProjectLookup
    private let publishDelay: Duration
    private var publish: (@Sendable (Data) async -> Void)?
    private var pending: Task<Void, Never>?
    private var isObserving = false

    init(store: TasksStore, projects: ProjectLookup, publishDelay: Duration = .milliseconds(300)) {
        self.store = store
        self.projects = projects
        self.publishDelay = publishDelay
    }

    func start(publish: @escaping @Sendable (Data) async -> Void) {
        guard self.publish == nil else { return }
        self.publish = publish
        isObserving = true
        observe()
        schedulePublish()
    }

    func stop() {
        isObserving = false
        pending?.cancel()
        pending = nil
        publish = nil
    }

    // MARK: - Yayın

    private func observe() {
        guard isObserving else { return }
        withObservationTracking {
            _ = store.entries
            _ = store.sources
            _ = store.agentLinks
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.schedulePublish()
                self?.observe()
            }
        }
    }

    private func schedulePublish() {
        guard pending == nil, let publish else { return }
        let delay = publishDelay
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            guard let data = RemoteTasksSnapshot.data(self.store) else { return }
            await publish(data)
        }
    }

    // MARK: - Komutlar

    func handleTaskCommand(action: String, payload: [String: Any]) async -> RemoteTaskCommandOutcome {
        switch action {
        case "tasks_subscribe":
            store.renewRemoteViewer()
            schedulePublish()
            return .success
        case "tasks_unsubscribe":
            store.endRemoteViewer()
            return .success
        case "task_create":
            return await create(payload)
        default:
            guard let key = Self.key(payload) else { return .failure("missing_task") }
            guard store.entry(key) != nil else { return .failure("task_not_found") }
            return await handle(action, key: key, payload: payload)
        }
    }

    private func handle(_ action: String, key: TaskKey, payload: [String: Any]) async -> RemoteTaskCommandOutcome {
        switch action {
        case "task_move":
            guard let status = (payload["status"] as? String).flatMap(TaskStatus.init(rawValue:)) else {
                return .failure("invalid_status")
            }
            store.move(key, to: status)
            return .success
        case "task_assign":
            return assign(key, userID: payload["userId"] as? String)
        case "task_detail":
            return detail(key)
        case "task_start":
            return await start(key, payload: payload)
        default:
            return .failure("unknown_action")
        }
    }

    private func assign(_ key: TaskKey, userID: String?) -> RemoteTaskCommandOutcome {
        guard let state = store.state(of: key.source), state.info?.canAssign == true else {
            return .failure("This source doesn't allow assigning from Lumi.")
        }
        guard let userID else {
            store.assign(key, to: nil)
            return .success
        }
        let candidates = store.assignOptions(for: key.source).map(\.user)
        guard let user = candidates.first(where: { $0.id == userID }) else { return .failure("unknown_user") }
        store.assign(key, to: user)
        return .success
    }

    private func detail(_ key: TaskKey) -> RemoteTaskCommandOutcome {
        guard let entry = store.entry(key) else { return .failure("task_not_found") }
        var data: [String: String] = ["prompt": store.agentPrompt(for: key)]
        if store.info(of: key.source)?.canRead(.body) == true, let body = entry.item.body { data["body"] = body }
        return RemoteTaskCommandOutcome(ok: true, data: data)
    }

    private func create(_ payload: [String: Any]) async -> RemoteTaskCommandOutcome {
        guard let source = (payload["sourceId"] as? String).map({ TaskSourceID($0) }),
              let title = (payload["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty
        else { return .failure("missing_title") }
        let status = (payload["status"] as? String).flatMap(TaskStatus.init(rawValue:)) ?? .todo
        switch await store.createTask(TaskDraft(title: title, status: status), in: source) {
        case .success(let key): return RemoteTaskCommandOutcome(ok: true, data: ["taskId": key.id])
        case .failure(let failure): return .failure(failure.summary)
        }
    }

    /// Mac'in Start'ı: proje (telefon seçtiyse o, yoksa eşleşme), yer (git'te
    /// varsayılan yeni workspace), kaynağın prompt şablonu.
    private func start(_ key: TaskKey, payload: [String: Any]) async -> RemoteTaskCommandOutcome {
        guard let entry = store.entry(key) else { return .failure("task_not_found") }
        if store.agentLink(for: key)?.state.isActive == true { return .failure("An agent is already working on this task.") }
        let known = projects.projectPaths()
        var projectPath = (payload["projectPath"] as? String).flatMap { known.contains($0) ? $0 : nil }
        if projectPath == nil {
            let origins = await store.origins(for: known)
            projectPath = TaskProjectMatcher.match(entry.item.project, in: known, origins: origins)
        }
        guard let projectPath else { return .failure("no_project") }
        let model = (payload["model"] as? String).flatMap(ClaudeModelAlias.init(rawValue:))
        let checkout: TaskCheckoutChoice
        if let path = payload["checkoutPath"] as? String, !path.isEmpty {
            checkout = .existing(path: path)
        } else if payload["checkout"] as? String != "existing", projects.isGit(projectPath) {
            checkout = .newWorkspace(projectPath: projectPath, branch: TaskAgentPrompt.branchName(for: entry.item))
        } else {
            checkout = .existing(path: projectPath)
        }
        let info = store.info(of: key.source)
        let assignToMe = info?.canAssign == true && info?.me != nil && entry.item.assignee?.id != info?.me?.id
        store.start(
            TaskAgentRequest(
                task: key, taskTitle: entry.item.title, checkout: checkout, agent: TaskAgentChoice(model: model),
                prompt: store.agentPrompt(for: key), details: store.agentDetails(for: key)
            ),
            moveToInProgress: true,
            assignToMe: assignToMe
        )
        return RemoteTaskCommandOutcome(ok: true, data: ["projectPath": projectPath])
    }

    static func key(_ payload: [String: Any]) -> TaskKey? {
        guard let source = payload["sourceId"] as? String, !source.isEmpty,
              let id = payload["taskId"] as? String, !id.isEmpty else { return nil }
        return TaskKey(source: TaskSourceID(source), id: id)
    }
}
