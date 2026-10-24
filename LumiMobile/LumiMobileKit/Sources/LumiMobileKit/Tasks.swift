import Foundation

/// Mac's Tasks board as the phone sees it (Mac decision 137, mobile addendum).
///
/// The phone never talks to the user's task server: tokens and adapters stay
/// on the Mac, which publishes this snapshot over the relay and executes the
/// phone's `task_*` commands. Bodies are not part of the snapshot (size) —
/// `task_detail` fetches them on demand.
public struct TasksSnapshot: Decodable, Sendable, Equatable {
    public let sources: [TaskSourceSummary]
    public let tasks: [RemoteTask]
    /// Milliseconds since 1970 — when the Mac built this snapshot.
    public let generatedAt: Double?
    /// Oldest Done tasks the Mac dropped to fit the relay frame limit.
    public let truncatedDone: Int

    public init(sources: [TaskSourceSummary], tasks: [RemoteTask], generatedAt: Double? = nil, truncatedDone: Int = 0) {
        self.sources = sources
        self.tasks = tasks
        self.generatedAt = generatedAt
        self.truncatedDone = truncatedDone
    }

    public static let empty = TasksSnapshot(sources: [], tasks: [])

    private enum CodingKeys: String, CodingKey { case sources, tasks, generatedAt, truncatedDone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerant: one malformed row must not hide the whole board.
        sources = (try? c.decode([Lossy<TaskSourceSummary>].self, forKey: .sources))?.compactMap(\.value) ?? []
        tasks = (try? c.decode([Lossy<RemoteTask>].self, forKey: .tasks))?.compactMap(\.value) ?? []
        generatedAt = try? c.decodeIfPresent(Double.self, forKey: .generatedAt)
        truncatedDone = (try? c.decodeIfPresent(Int.self, forKey: .truncatedDone)) ?? 0
    }

    public func source(_ id: String) -> TaskSourceSummary? {
        sources.first { $0.id == id }
    }
}

/// Decodes an element or yields nil instead of failing the array.
struct Lossy<T: Decodable & Sendable>: Decodable, Sendable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

public enum RemoteTaskStatus: String, CaseIterable, Sendable, Codable, Hashable {
    case todo
    case inProgress = "in_progress"
    case inReview = "in_review"
    case done

    public var title: String {
        switch self {
        case .todo: "Todo"
        case .inProgress: "In Progress"
        case .inReview: "In Review"
        case .done: "Done"
        }
    }

    /// Swipe action target ("move along"). Done has none.
    public var next: RemoteTaskStatus? {
        switch self {
        case .todo: .inProgress
        case .inProgress: .inReview
        case .inReview: .done
        case .done: nil
        }
    }
}

public struct TaskUserRef: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count >= 2 { return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
        return String(name.prefix(2)).uppercased()
    }
}

public struct TaskSourceSummary: Decodable, Sendable, Equatable, Identifiable {
    public enum Phase: String, Decodable, Sendable {
        case loading, ready, offline, failing, reconnect, unsupported
    }

    public let id: String
    public let name: String
    public let kind: String
    public let phase: Phase
    public let phaseMessage: String?
    public let lastUpdated: Double?
    public let capabilities: [String]
    public let fields: [String: String]
    public let canAssign: Bool
    public let me: TaskUserRef?
    public let users: [TaskUserRef]

    public init(id: String, name: String, kind: String = "custom", phase: Phase = .ready, phaseMessage: String? = nil,
                lastUpdated: Double? = nil, capabilities: [String] = [], fields: [String: String] = [:],
                canAssign: Bool = false, me: TaskUserRef? = nil, users: [TaskUserRef] = []) {
        self.id = id
        self.name = name
        self.kind = kind
        self.phase = phase
        self.phaseMessage = phaseMessage
        self.lastUpdated = lastUpdated
        self.capabilities = capabilities
        self.fields = fields
        self.canAssign = canAssign
        self.me = me
        self.users = users
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, phase, phaseMessage, lastUpdated, capabilities, fields, canAssign, me, users
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "custom"
        phase = (try? c.decode(Phase.self, forKey: .phase)) ?? .ready
        phaseMessage = try? c.decodeIfPresent(String.self, forKey: .phaseMessage)
        lastUpdated = try? c.decodeIfPresent(Double.self, forKey: .lastUpdated)
        capabilities = (try? c.decodeIfPresent([String].self, forKey: .capabilities)) ?? []
        fields = (try? c.decodeIfPresent([String: String].self, forKey: .fields)) ?? [:]
        canAssign = (try? c.decodeIfPresent(Bool.self, forKey: .canAssign)) ?? false
        me = try? c.decodeIfPresent(TaskUserRef.self, forKey: .me)
        users = (try? c.decodeIfPresent([TaskUserRef].self, forKey: .users)) ?? []
    }

    public var canCreate: Bool { capabilities.contains("create") && phase == .ready }
    public func canRead(_ field: String) -> Bool { fields[field] != nil }

    /// Assignment picker order: You first, then everyone else by name (Mac parity).
    public var assignOptions: [TaskUserRef] {
        var result: [TaskUserRef] = []
        if let me { result.append(me) }
        result += users.filter { $0.id != me?.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }
}

public struct RemoteTaskAgent: Decodable, Sendable, Equatable {
    public enum State: String, Decodable, Sendable {
        case starting, working, needsInput, idle, submitted, exited

        public var title: String {
            switch self {
            case .starting: "Starting"
            case .working: "Working"
            case .needsInput: "Needs input"
            case .idle: "Waiting"
            case .submitted: "Submitted for review"
            case .exited: "Exited"
            }
        }

        public var isActive: Bool { [.starting, .working, .needsInput, .idle].contains(self) }
    }

    public let state: State
    public let title: String
    public let checkout: String?
    /// The agent terminal's id — also the phone's session id (opens its chat).
    public let terminalId: String?
    public let summary: String?
    public let reattached: Bool

    public init(state: State, title: String, checkout: String? = nil, terminalId: String? = nil,
                summary: String? = nil, reattached: Bool = false) {
        self.state = state
        self.title = title
        self.checkout = checkout
        self.terminalId = terminalId
        self.summary = summary
        self.reattached = reattached
    }

    private enum CodingKeys: String, CodingKey { case state, title, checkout, terminalId, summary, reattached }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = (try? c.decode(State.self, forKey: .state)) ?? .idle
        title = (try? c.decode(String.self, forKey: .title)) ?? "Claude"
        checkout = try? c.decodeIfPresent(String.self, forKey: .checkout)
        terminalId = try? c.decodeIfPresent(String.self, forKey: .terminalId)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        reattached = (try? c.decodeIfPresent(Bool.self, forKey: .reattached)) ?? false
    }
}

public struct RemoteTask: Decodable, Sendable, Equatable, Identifiable {
    public struct ProjectRef: Decodable, Sendable, Equatable {
        public let key: String
        public let name: String?
        public var displayName: String { name ?? key }

        public init(key: String, name: String? = nil) {
            self.key = key
            self.name = name
        }
    }

    public let source: String
    public let id: String
    public var title: String
    public var status: RemoteTaskStatus
    public let priority: String?
    public let labels: [String]
    public var assignee: TaskUserRef?
    public let project: ProjectRef?
    public let updatedAt: Double
    public let needsAttention: Bool
    public let imageCount: Int
    public let hasBody: Bool
    public let url: String?
    public let agent: RemoteTaskAgent?

    public init(source: String, id: String, title: String, status: RemoteTaskStatus, priority: String? = nil,
                labels: [String] = [], assignee: TaskUserRef? = nil, project: ProjectRef? = nil,
                updatedAt: Double = 0, needsAttention: Bool = false, imageCount: Int = 0, hasBody: Bool = false,
                url: String? = nil, agent: RemoteTaskAgent? = nil) {
        self.source = source
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.labels = labels
        self.assignee = assignee
        self.project = project
        self.updatedAt = updatedAt
        self.needsAttention = needsAttention
        self.imageCount = imageCount
        self.hasBody = hasBody
        self.url = url
        self.agent = agent
    }

    /// Unique across sources.
    public var key: TaskRef { TaskRef(source: source, id: id) }

    private enum CodingKeys: String, CodingKey {
        case source, id, title, status, priority, labels, assignee, project, updatedAt, needsAttention,
             imageCount, hasBody, url, agent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        status = (try? c.decode(RemoteTaskStatus.self, forKey: .status)) ?? .todo
        priority = try? c.decodeIfPresent(String.self, forKey: .priority)
        labels = (try? c.decodeIfPresent([String].self, forKey: .labels)) ?? []
        assignee = try? c.decodeIfPresent(TaskUserRef.self, forKey: .assignee)
        project = try? c.decodeIfPresent(ProjectRef.self, forKey: .project)
        updatedAt = (try? c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
        needsAttention = (try? c.decodeIfPresent(Bool.self, forKey: .needsAttention)) ?? false
        imageCount = (try? c.decodeIfPresent(Int.self, forKey: .imageCount)) ?? 0
        hasBody = (try? c.decodeIfPresent(Bool.self, forKey: .hasBody)) ?? false
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        agent = try? c.decodeIfPresent(RemoteTaskAgent.self, forKey: .agent)
    }
}

public struct TaskRef: Hashable, Sendable {
    public let source: String
    public let id: String

    public init(source: String, id: String) {
        self.source = source
        self.id = id
    }

    public var identity: String { source + "|" + id }
}

/// `task_detail` reply: the body and the exact prompt the Mac would send.
public struct TaskDetail: Sendable, Equatable {
    public let body: String?
    public let prompt: String?

    public init(body: String?, prompt: String?) {
        self.body = body
        self.prompt = prompt
    }
}

/// Phone-side list shaping (pure): filter + sections in board order.
public enum TaskList {
    public struct Section: Sendable, Equatable, Identifiable {
        public let status: RemoteTaskStatus
        public let tasks: [RemoteTask]
        public var id: RemoteTaskStatus { status }
    }

    public static func sections(
        _ tasks: [RemoteTask], source: String?, statuses: Set<RemoteTaskStatus>, mineOnly: Bool, me: (String) -> String?
    ) -> [Section] {
        let filtered = tasks.filter { task in
            if let source, task.source != source { return false }
            guard statuses.contains(task.status) else { return false }
            if mineOnly {
                guard let myID = me(task.source), task.assignee?.id == myID else { return false }
            }
            return true
        }
        let grouped = Dictionary(grouping: filtered, by: \.status)
        return RemoteTaskStatus.allCases.compactMap { status in
            guard let items = grouped[status], !items.isEmpty else { return nil }
            return Section(status: status, tasks: items.sorted(by: order))
        }
    }

    /// Attention first, then higher priority, then most recently updated (Mac parity).
    static func order(_ lhs: RemoteTask, _ rhs: RemoteTask) -> Bool {
        if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
        let left = priorityRank(lhs.priority), right = priorityRank(rhs.priority)
        if left != right { return left > right }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id < rhs.id
    }

    static func priorityRank(_ raw: String?) -> Int {
        ["none", "low", "medium", "high", "urgent"].firstIndex(of: raw ?? "none") ?? 0
    }
}
