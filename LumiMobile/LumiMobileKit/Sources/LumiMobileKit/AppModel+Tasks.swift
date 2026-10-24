import Foundation
import LumiWire

/// Start-from-phone progress (the Tasks start sheet observes it).
public enum TaskStartState: Sendable, Equatable {
    case idle
    case sending
    case succeeded
    /// `needsProject`: the Mac found no Lumi project for the task — pick one.
    case failed(String, needsProject: Bool = false)
}

/// An optimistic edit shown until the Mac's snapshot agrees or the command fails.
struct PendingTaskEdit: Sendable, Equatable {
    var status: RemoteTaskStatus?
    var assignee: TaskUserRef??
    var commandIds: Set<String>
}

enum TaskCommandKind: Sendable {
    case edit(TaskRef)
    case detail(TaskRef)
    case start
    case create
    case other
}

/// Tasks on the phone (Mac decision 137, mobile addendum).
///
/// The phone is a window onto the Mac's board: it never talks to the task
/// server. While the Tasks screen is visible it holds a viewer lease on the Mac
/// (`tasks_subscribe`, renewed every 30 s) so the Mac keeps the board fresh —
/// nobody looking means no server requests (Mac user decision 6).
extension AppModel {
    // MARK: - Derived

    /// The snapshot with optimistic edits applied.
    public var displayedTasks: [RemoteTask] {
        (tasksSnapshot?.tasks ?? []).map { task in
            guard let edit = pendingTaskEdits[task.key.identity] else { return task }
            var copy = task
            if let status = edit.status { copy.status = status }
            if let assignee = edit.assignee { copy.assignee = assignee }
            return copy
        }
    }

    public var taskSources: [TaskSourceSummary] { tasksSnapshot?.sources ?? [] }

    public func task(_ ref: TaskRef) -> RemoteTask? {
        displayedTasks.first { $0.key == ref }
    }

    public func taskSource(_ id: String) -> TaskSourceSummary? {
        tasksSnapshot?.source(id)
    }

    // MARK: - Visibility lease

    /// The Tasks screen appeared/disappeared.
    public func setTasksVisible(_ visible: Bool) {
        guard visible != tasksVisible else { return }
        tasksVisible = visible
        tasksRenewTask?.cancel()
        tasksRenewTask = nil
        guard visible else {
            sendTaskCommand(.tasksUnsubscribe, kind: .other)
            return
        }
        sendTasksSubscribe()
        let interval = tasksRenewInterval
        tasksRenewTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.sendTasksSubscribe()
            }
        }
    }

    func sendTasksSubscribe() {
        sendTaskCommand(.tasksSubscribe, kind: .other)
    }

    // MARK: - Commands

    public func moveTask(_ ref: TaskRef, to status: RemoteTaskStatus) {
        guard task(ref)?.status != status else { return }
        let id = sendTaskCommand(.taskMove(source: ref.source, taskId: ref.id, status: status), kind: .edit(ref))
        var edit = pendingTaskEdits[ref.identity] ?? PendingTaskEdit(commandIds: [])
        edit.status = status
        edit.commandIds.insert(id)
        pendingTaskEdits[ref.identity] = edit
    }

    public func assignTask(_ ref: TaskRef, to user: TaskUserRef?) {
        let id = sendTaskCommand(.taskAssign(source: ref.source, taskId: ref.id, userId: user?.id), kind: .edit(ref))
        var edit = pendingTaskEdits[ref.identity] ?? PendingTaskEdit(commandIds: [])
        edit.assignee = .some(user)
        edit.commandIds.insert(id)
        pendingTaskEdits[ref.identity] = edit
    }

    public func loadTaskDetail(_ ref: TaskRef) {
        sendTaskCommand(.taskDetail(source: ref.source, taskId: ref.id), kind: .detail(ref))
    }

    public func detail(for ref: TaskRef) -> TaskDetail? {
        taskDetails[ref.identity]
    }

    public func startTask(_ ref: TaskRef, model: ClaudeModelAlias?, projectPath: String?, existingCheckout: Bool) {
        taskStartState = .sending
        sendTaskCommand(
            .taskStart(source: ref.source, taskId: ref.id, model: model, projectPath: projectPath, existingCheckout: existingCheckout),
            kind: .start
        )
    }

    public func resetTaskStart() {
        taskStartState = .idle
    }

    public func createTask(source: String, title: String, status: RemoteTaskStatus = .todo) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendTaskCommand(.taskCreate(source: source, title: trimmed, status: status), kind: .create)
    }

    public func clearTaskError() {
        taskError = nil
    }

    // MARK: - Inbound

    func applyTasks(_ snapshot: TasksSnapshot) {
        tasksSnapshot = snapshot
        // An optimistic edit ends once the Mac shows it (or the task is gone).
        for (identity, edit) in pendingTaskEdits {
            guard let task = snapshot.tasks.first(where: { $0.key.identity == identity }) else {
                pendingTaskEdits[identity] = nil
                continue
            }
            if edit.commandIds.isEmpty, Self.isReflected(edit, in: task) { pendingTaskEdits[identity] = nil }
        }
    }

    /// Returns true when the result belonged to a task command.
    func handleTaskResult(_ result: CommandResult) -> Bool {
        guard let kind = taskCommands.removeValue(forKey: result.commandId) else { return false }
        switch kind {
        case .edit(let ref):
            pendingTaskEdits[ref.identity]?.commandIds.remove(result.commandId)
            if !result.ok {
                pendingTaskEdits[ref.identity] = nil
                taskError = Self.describeTaskError(result.error)
            } else if let edit = pendingTaskEdits[ref.identity], edit.commandIds.isEmpty,
                      let task = tasksSnapshot?.tasks.first(where: { $0.key == ref }),
                      Self.isReflected(edit, in: task) {
                pendingTaskEdits[ref.identity] = nil
            }
        case .detail(let ref):
            if result.ok {
                taskDetails[ref.identity] = TaskDetail(body: result.data?["body"], prompt: result.data?["prompt"])
            }
        case .start:
            if result.ok {
                taskStartState = .succeeded
            } else if result.error == "no_project" {
                taskStartState = .failed("No Lumi project matches this task — pick one.", needsProject: true)
            } else {
                taskStartState = .failed(Self.describeTaskError(result.error))
            }
        case .create:
            if !result.ok { taskError = Self.describeTaskError(result.error) }
        case .other:
            break
        }
        return true
    }

    /// The Mac's task already shows every field of the optimistic edit.
    static func isReflected(_ edit: PendingTaskEdit, in task: RemoteTask) -> Bool {
        let statusDone = edit.status.map { $0 == task.status } ?? true
        let assigneeDone = edit.assignee.map { $0?.id == task.assignee?.id } ?? true
        return statusDone && assigneeDone
    }

    static func describeTaskError(_ raw: String?) -> String {
        switch raw {
        case nil: "The Mac couldn't do that."
        case "tasks_unavailable": "Tasks aren't available on this Mac — update Lumi on the Mac."
        case "task_not_found": "This task no longer exists."
        case "unknown_user": "That person isn't on this task source."
        case "invalid_status": "Unknown status."
        case "missing_title": "A task needs a title."
        case "no connection": "No connection to your Mac."
        case let message?: message
        }
    }

    @discardableResult
    func sendTaskCommand(_ action: CommandAction, kind: TaskCommandKind) -> String {
        commandCounter += 1
        let commandId = "ph-\(commandCounter)"
        taskCommands[commandId] = kind
        Task {
            let ok = await client.send(command: OutgoingCommand(commandId: commandId, action: action))
            if !ok {
                _ = handleTaskResult(CommandResult(commandId: commandId, ok: false, error: "no connection"))
            }
        }
        return commandId
    }
}
