import Foundation
import LumiKit

/// `TaskProviding` test ikamesi: ağ yok, gecikme yok; veri ve hatalar
/// scriptlenir, çağrılar sayılır ("route kapalıyken istek atılmaz" testleri).
public actor FakeTaskProvider: TaskProviding {
    public var info: TaskSourceInfo
    public var tasks: [TaskItem]
    public var users: [TaskUser]
    public var projects: [TaskProjectRef]
    /// Doluysa ilgili çağrı bu hatayı fırlatır.
    public var discoverError: TaskProviderError?
    public var listError: TaskProviderError?
    public var updateError: TaskProviderError?
    /// `update` bu kapı açılana kadar bekler (uçuştaki yazım testleri).
    private var updateGate: CheckedContinuation<Void, Never>?
    private var holdsUpdates = false

    public private(set) var discoverCount = 0
    public private(set) var listCount = 0
    public private(set) var updates: [(id: String, patch: TaskPatch)] = []
    public private(set) var created: [TaskDraft] = []
    public private(set) var deleted: [String] = []

    public init(
        info: TaskSourceInfo = .fakeFull(),
        tasks: [TaskItem] = [],
        users: [TaskUser] = [],
        projects: [TaskProjectRef] = []
    ) {
        self.info = info
        self.tasks = tasks
        self.users = users
        self.projects = projects
    }

    public func setTasks(_ tasks: [TaskItem]) { self.tasks = tasks }
    public func setInfo(_ info: TaskSourceInfo) { self.info = info }
    public func setDiscoverError(_ error: TaskProviderError?) { discoverError = error }
    public func setListError(_ error: TaskProviderError?) { listError = error }
    public func setUpdateError(_ error: TaskProviderError?) { updateError = error }

    public func holdUpdates() { holdsUpdates = true }

    public func releaseUpdates() {
        holdsUpdates = false
        updateGate?.resume()
        updateGate = nil
    }

    public func discover() async throws -> TaskSourceInfo {
        discoverCount += 1
        if let discoverError { throw discoverError }
        return info
    }

    public func listTasks() async throws -> [TaskItem] {
        listCount += 1
        if let listError { throw listError }
        return tasks
    }

    public func update(taskID: String, patch: TaskPatch) async throws -> TaskItem {
        updates.append((taskID, patch))
        if holdsUpdates {
            await withCheckedContinuation { updateGate = $0 }
        }
        if let updateError { throw updateError }
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { throw TaskProviderError.notFound }
        tasks[index] = patch.applied(to: tasks[index], now: tasks[index].updatedAt.addingTimeInterval(1))
        return tasks[index]
    }

    public func create(_ draft: TaskDraft) async throws -> TaskItem {
        created.append(draft)
        let item = TaskItem(
            id: "NEW-\(created.count)", title: draft.title, status: draft.status,
            updatedAt: Date(timeIntervalSince1970: 1_000), assignee: draft.assignee
        )
        tasks.append(item)
        return item
    }

    public func delete(taskID: String) async throws {
        deleted.append(taskID)
        tasks.removeAll { $0.id == taskID }
    }

    public func listUsers() async throws -> [TaskUser] { users }
    public func listProjects() async throws -> [TaskProjectRef] { projects }
}

/// Kaynak türüne göre önceden kurulmuş fake'i döndürür.
public final class FakeTaskProviderFactory: TaskProviderMaking, @unchecked Sendable {
    private let lock = NSLock()
    private var providers: [TaskProviderKind: FakeTaskProvider]

    public init(providers: [TaskProviderKind: FakeTaskProvider] = [:]) {
        self.providers = providers
    }

    public func provider(for kind: TaskProviderKind) -> FakeTaskProvider {
        lock.lock()
        defer { lock.unlock() }
        if let existing = providers[kind] { return existing }
        let made = FakeTaskProvider()
        providers[kind] = made
        return made
    }

    public func makeProvider(for source: TaskSource, token: String?) -> any TaskProviding {
        provider(for: source.kind)
    }
}

public extension TaskSourceInfo {
    /// Her yeteneği ve alanı (yazılabilir) beyan eden kaynak.
    static func fakeFull(me: TaskUser? = TaskUser(id: "me", name: "Me")) -> TaskSourceInfo {
        TaskSourceInfo(
            name: "Fake",
            capabilities: Set(TaskCapability.allCases),
            fields: Dictionary(uniqueKeysWithValues: TaskField.allCases.map { ($0, .readWrite) }),
            me: me
        )
    }
}

public extension TaskItem {
    static func fake(
        id: String,
        title: String? = nil,
        status: TaskStatus = .todo,
        updatedAt: Date = Date(timeIntervalSince1970: 0),
        priority: TaskPriority? = nil,
        assignee: TaskUser? = nil,
        project: TaskProjectRef? = nil,
        needsAttention: Bool = false
    ) -> TaskItem {
        TaskItem(
            id: id, title: title ?? "Task \(id)", status: status, updatedAt: updatedAt,
            project: project, priority: priority, assignee: assignee, needsAttention: needsAttention
        )
    }
}
