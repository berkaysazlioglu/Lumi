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
        // Gerçek URLSession / demo gecikmesi gibi: iptal edilmiş görevde istek düşer.
        try Task.checkCancellation()
        if let listError { throw listError }
        return tasks
    }

    public func update(taskID: String, patch: TaskPatch) async throws -> TaskItem {
        updates.append((taskID, patch))
        try Task.checkCancellation()
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

/// Görsel yükleyici ikamesi: adresi olduğu gibi döner, istekleri sayar.
public actor FakeTaskImageLoader: TaskImageLoading {
    public private(set) var requests: [URL] = []
    public var error: TaskProviderError?

    public init() {}

    public func setError(_ error: TaskProviderError?) { self.error = error }

    public func localFile(for url: URL, authorization: String?) async throws -> URL {
        requests.append(url)
        if let error { throw error }
        return url
    }

    public private(set) var attachedTasks: [TaskKey] = []
    public private(set) var removedAttachments: [TaskKey] = []
    public private(set) var removedSources: [TaskSourceID] = []
    public private(set) var evicted: [URL] = []

    public func attachments(
        for task: TaskKey, images: [TaskImage], authorization: @escaping @Sendable (URL) -> String?
    ) async -> (directory: URL, files: [URL]) {
        attachedTasks.append(task)
        let directory = URL(fileURLWithPath: "/attachments/\(task.id)")
        return (directory, images.enumerated().map { directory.appendingPathComponent("\($0.offset + 1)-\($0.element.displayName)") })
    }

    public func removeAttachments(for tasks: [TaskKey]) async { removedAttachments += tasks }
    public func removeAttachments(source: TaskSourceID) async { removedSources.append(source) }
    public func evict(_ urls: [URL]) async { evicted += urls }
}

/// Ajan koşucusu ikamesi: verilen olayları sırayla yayınlar.
@MainActor
public final class FakeTaskAgentRunner: TaskAgentRunning {
    private var script: [TaskAgentEvent]
    public var reattachScript: [TaskAgentEvent] = []
    public private(set) var requests: [TaskAgentRequest] = []
    public private(set) var reattachedSessions: [String] = []

    public init(script: [TaskAgentEvent] = [.started(nil), .state(.working)]) {
        self.script = script
    }

    public var isPreview: Bool { false }

    public func start(_ request: TaskAgentRequest) -> AsyncStream<TaskAgentEvent> {
        requests.append(request)
        return Self.stream(script)
    }

    public func reattach(sessionID: String, task: TaskKey) -> AsyncStream<TaskAgentEvent> {
        reattachedSessions.append(sessionID)
        return Self.stream(reattachScript)
    }

    private static func stream(_ events: [TaskAgentEvent]) -> AsyncStream<TaskAgentEvent> {
        AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// Token deposu ikamesi: bellek içi; okuma/yazma hatası scriptlenebilir.
public actor FakeTaskCredentialStore: TaskCredentialStoring {
    public private(set) var tokens: [TaskSourceID: String] = [:]
    public var readFailure: String?
    public var writeFails = false

    public init(tokens: [TaskSourceID: String] = [:]) {
        self.tokens = tokens
    }

    public func setReadFailure(_ detail: String?) { readFailure = detail }
    public func setWriteFails(_ fails: Bool) { writeFails = fails }

    public func token(for source: TaskSourceID) async -> KeychainReadResult {
        if let readFailure { return .failed(detail: readFailure) }
        return tokens[source].map { .found($0) } ?? .missing
    }

    public func setToken(_ token: String, for source: TaskSourceID) async throws {
        if writeFails { throw TaskProviderError.unreachable("keychain locked") }
        tokens[source] = token
    }

    public func deleteToken(for source: TaskSourceID) async throws {
        tokens[source] = nil
    }
}

/// Scriptli HTTP taşıması: (yöntem, yol) → yanıt; istekleri kaydeder.
/// Senkron kurulur (sınıf + kilit) — JSON sözlükleri actor sınırından geçmesin.
public final class FakeHTTPTransport: HTTPTransporting, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var routes: [String: [HTTPResponse]] = [:]
    private var networkError: URLError?

    public init() {}

    public var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Aynı uca birden çok yanıt verilirse sırayla tüketilir; sonuncu kalır.
    public func respond(_ method: String, _ path: String, status: Int, json: Any? = nil, raw: String? = nil, headers: [String: String] = [:]) {
        let body: Data = if let json { (try? JSONSerialization.data(withJSONObject: json)) ?? Data() } else { Data((raw ?? "").utf8) }
        lock.lock()
        routes["\(method) \(path)", default: []].append(HTTPResponse(status: status, body: body, headers: headers))
        lock.unlock()
    }

    public func setNetworkError(_ error: URLError?) {
        lock.lock()
        networkError = error
        lock.unlock()
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        try next(for: request).get()
    }

    private func next(for request: URLRequest) -> Result<HTTPResponse, URLError> {
        lock.withLock {
            recorded.append(request)
            if let networkError { return .failure(networkError) }
            let key = "\(request.httpMethod ?? "GET") \(request.url?.path(percentEncoded: false) ?? "")"
            guard var queue = routes[key], !queue.isEmpty else {
                return .success(HTTPResponse(status: 404, body: Data(#"{"error":{"code":"not_found","message":"no fake route"}}"#.utf8)))
            }
            let response = queue.count > 1 ? queue.removeFirst() : queue[0]
            routes[key] = queue
            return .success(response)
        }
    }

}

/// Task ajanı MCP sunucusu ikamesi: kayıtları tutar, `submit` ile aracı tetikler.
public actor FakeTaskAgentTools: TaskAgentToolServing {
    public private(set) var registered: [(details: String, session: TaskAgentToolSession)] = []
    public private(set) var unregistered: [TaskAgentToolSession] = []
    private var handlers: [String: @Sendable (String) async -> String] = [:]
    public var fails = false

    public init() {}

    public func setFails(_ fails: Bool) { self.fails = fails }

    public func register(details: String, onSubmit: @escaping @Sendable (String) async -> String) async throws -> TaskAgentToolSession {
        if fails { throw TaskProviderError.unreachable("listener failed") }
        let session = TaskAgentToolSession(configPath: "/tmp/mcp-\(registered.count).json", token: "tok-\(registered.count)")
        registered.append((details, session))
        handlers[session.token] = onSubmit
        return session
    }

    public func unregister(_ session: TaskAgentToolSession) async {
        unregistered.append(session)
        handlers[session.token] = nil
    }

    /// Ajanın `submit_for_review` çağrısını taklit eder.
    public func submit(token: String, summary: String) async -> String? {
        guard let handler = handlers[token] else { return nil }
        return await handler(summary)
    }
}
