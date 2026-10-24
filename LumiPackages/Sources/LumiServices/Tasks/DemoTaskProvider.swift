import Foundation
import LumiKit

/// Bellek içi örnek kaynak (Tasks planı, Faz 1).
///
/// Board'u gerçek bir sunucu olmadan denemek içindir: tüm yetenekleri ve
/// alanları beyan eder, her çağrıda kısa bir ağ gecikmesi taklit eder. Veri
/// uygulama kapanınca gider.
public actor DemoTaskProvider: TaskProviding {
    /// Ağ gecikmesi taklidi — iyimser güncellemenin ve yükleme durumlarının
    /// gözle görülebilmesi için.
    private let latency: Duration
    private let me: TaskUser
    private let users: [TaskUser]
    private let projects: [TaskProjectRef]
    private var tasks: [TaskItem]
    private var nextID: Int

    public init(latency: Duration = .milliseconds(350), meName: String = NSFullUserName(), now: Date = Date()) {
        self.latency = latency
        let me = TaskUser(id: "u_me", name: meName.isEmpty ? "Me" : meName, email: nil)
        let users = [
            me,
            TaskUser(id: "u_ada", name: "Ada Lovelace", email: "ada@example.com"),
            TaskUser(id: "u_linus", name: "Linus Park", email: "linus@example.com"),
            TaskUser(id: "u_grace", name: "Grace Hopper", email: "grace@example.com"),
        ]
        let projects = [
            TaskProjectRef(key: "lumi", name: "Lumi"),
            TaskProjectRef(key: "api", name: "Backend API"),
            TaskProjectRef(key: "web", name: "Marketing site"),
        ]
        self.me = me
        self.users = users
        self.projects = projects
        tasks = Self.sampleTasks(users: users, projects: projects, now: now)
        nextID = tasks.count + 1
    }

    public func discover() async throws -> TaskSourceInfo {
        try await simulateLatency()
        return TaskSourceInfo(
            name: "Demo board",
            capabilities: Set(TaskCapability.allCases),
            fields: [
                .body: .readWrite, .project: .readWrite, .priority: .readWrite, .labels: .read,
                .assignee: .readWrite, .dueDate: .read, .url: .read,
            ],
            me: me
        )
    }

    public func listTasks() async throws -> [TaskItem] {
        try await simulateLatency()
        return tasks
    }

    public func update(taskID: String, patch: TaskPatch) async throws -> TaskItem {
        try await simulateLatency()
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { throw TaskProviderError.notFound }
        tasks[index] = patch.applied(to: tasks[index], now: Date())
        return tasks[index]
    }

    public func create(_ draft: TaskDraft) async throws -> TaskItem {
        try await simulateLatency()
        let now = Date()
        let item = TaskItem(
            id: "DEMO-\(nextID)",
            title: draft.title,
            status: draft.status,
            updatedAt: now,
            createdAt: now,
            body: draft.body,
            project: draft.projectKey.flatMap { key in projects.first { $0.key == key } ?? TaskProjectRef(key: key) },
            priority: draft.priority,
            assignee: draft.assignee
        )
        nextID += 1
        tasks.append(item)
        return item
    }

    public func delete(taskID: String) async throws {
        try await simulateLatency()
        guard tasks.contains(where: { $0.id == taskID }) else { throw TaskProviderError.notFound }
        tasks.removeAll { $0.id == taskID }
    }

    public func listUsers() async throws -> [TaskUser] {
        try await simulateLatency()
        return users
    }

    public func listProjects() async throws -> [TaskProjectRef] {
        try await simulateLatency()
        return projects
    }

    private func simulateLatency() async throws {
        guard latency > .zero else { return }
        try await Task.sleep(for: latency)
    }

    // MARK: - Örnek veri

    private static func sampleTasks(users: [TaskUser], projects: [TaskProjectRef], now: Date) -> [TaskItem] {
        let me = users[0], ada = users[1], linus = users[2], grace = users[3]
        let lumi = projects[0], api = projects[1], web = projects[2]
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        func ahead(_ days: Double) -> Date { now.addingTimeInterval(days * 86400) }
        var items: [TaskItem] = [
            TaskItem(
                id: "DEMO-1", title: "Board drag & drop between columns", status: .inProgress,
                updatedAt: ago(1), body: """
                Cards move between **Todo / In Progress / In Review / Done** by dragging.

                - Optimistic update, reverted on failure
                - Keep the card's position stable while the request is in flight
                """,
                project: lumi, priority: .high, labels: ["ui", "tasks"], assignee: me, dueDate: ahead(2),
                url: URL(string: "https://example.com/tasks/DEMO-1")
            ),
            TaskItem(
                id: "DEMO-2", title: "Rate limit the public tasks endpoint", status: .todo, updatedAt: ago(5),
                body: "Return `429` with `Retry-After` when a token exceeds 60 requests/minute.",
                project: api, priority: .urgent, labels: ["security"], assignee: linus
            ),
            TaskItem(
                id: "DEMO-3", title: "Token rotation endpoint", status: .todo, updatedAt: ago(20),
                body: "Let users rotate their Lumi token without redeploying.",
                project: api, priority: .medium, labels: ["auth"]
            ),
            TaskItem(
                id: "DEMO-4", title: "Pricing page copy review", status: .inReview, updatedAt: ago(3),
                project: web, priority: .low, labels: ["copy"], assignee: grace,
                url: URL(string: "https://example.com/tasks/DEMO-4")
            ),
            TaskItem(
                id: "DEMO-5", title: "Paginate GET /tasks", status: .inReview, updatedAt: ago(7),
                body: "Cursor based: `?cursor=&limit=` → `{ tasks, nextCursor }`.",
                project: api, priority: .high, labels: ["protocol"], assignee: me
            ),
            TaskItem(
                id: "DEMO-6", title: "Empty state illustration", status: .todo, updatedAt: ago(30),
                project: web, priority: TaskPriority.none, assignee: ada
            ),
            TaskItem(
                id: "DEMO-7", title: "Investigate flaky orchestrator test", status: .inProgress, updatedAt: ago(2),
                body: "Fails roughly 1 in 20 runs on CI. Probably a fixed sleep somewhere.",
                project: lumi, priority: .medium, labels: ["ci"], assignee: ada
            ),
            TaskItem(
                id: "DEMO-8", title: "Status came back as \"blocked\"", status: .todo, updatedAt: ago(9),
                body: "The server sent a status Lumi doesn't know, so this task is flagged.",
                project: lumi, needsAttention: true
            ),
        ]
        let doneTitles = [
            "Discovery endpoint", "Bearer token middleware", "Task model migration", "Seed demo data",
            "Health check route", "CORS for localhost", "Deploy to staging", "Error envelope",
        ]
        for (offset, title) in doneTitles.enumerated() {
            items.append(TaskItem(
                id: "DEMO-\(items.count + 1)", title: title, status: .done,
                updatedAt: ago(Double(24 + offset * 11)),
                project: offset.isMultiple(of: 2) ? api : lumi,
                assignee: [me, ada, linus, grace][offset % 4]
            ))
        }
        return items
    }
}

/// Canlı adapter fabrikası. `custom` adapter'ı protokol fazında (Faz 2) gelir;
/// o zamana kadar bağlanmayı açık bir mesajla reddeder.
public struct LiveTaskProviderFactory: TaskProviderMaking {
    public init() {}

    public func makeProvider(for source: TaskSource, token: String?) -> any TaskProviding {
        switch source.kind {
        case .demo: DemoTaskProvider()
        case .custom, .github, .linear: UnavailableTaskProvider(kind: source.kind)
        }
    }
}

/// Henüz yazılmamış adapter: her çağrı aynı açıklayıcı hatayı fırlatır.
public struct UnavailableTaskProvider: TaskProviding {
    let kind: TaskProviderKind

    public init(kind: TaskProviderKind) {
        self.kind = kind
    }

    private var error: TaskProviderError {
        .unsupported("\(kind.title) connections in this build — protocol support arrives in the next phase")
    }

    public func discover() async throws -> TaskSourceInfo { throw error }
    public func listTasks() async throws -> [TaskItem] { throw error }
    public func update(taskID: String, patch: TaskPatch) async throws -> TaskItem { throw error }
    public func create(_ draft: TaskDraft) async throws -> TaskItem { throw error }
    public func delete(taskID: String) async throws { throw error }
    public func listUsers() async throws -> [TaskUser] { throw error }
    public func listProjects() async throws -> [TaskProjectRef] { throw error }
}
