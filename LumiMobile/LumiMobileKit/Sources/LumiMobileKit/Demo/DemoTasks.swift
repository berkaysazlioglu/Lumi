import Foundation

/// Demo mode's Tasks board (Mac decision 137, mobile addendum): a small board
/// the fake Mac answers `task_*` commands against, so the phone UI can be
/// tried without a Mac. Agent links point at existing demo sessions, so
/// `Open Chat` lands in a real-looking conversation.
struct DemoTaskBoard: Sendable {
    static let sourceID = "demo-source"
    private static let me = TaskUserRef(id: "u_me", name: "Demo User")
    private static let ada = TaskUserRef(id: "u_ada", name: "Ada Lovelace")
    private static let linus = TaskUserRef(id: "u_linus", name: "Linus Park")

    private(set) var tasks: [RemoteTask]
    private var bodies: [String: String]
    private var nextID = 20

    init(nowMs: Double) {
        func ago(_ hours: Double) -> Double { nowMs - hours * 3_600_000 }
        let game = RemoteTask.ProjectRef(key: "word-puzzle", name: "Word Puzzle")
        let lumi = RemoteTask.ProjectRef(key: "lumi", name: "Lumi")
        tasks = [
            RemoteTask(source: Self.sourceID, id: "WP-12", title: "Daily rewards calendar screen", status: .inProgress,
                       priority: "high", labels: ["ui"], assignee: Self.me, project: game, updatedAt: ago(1),
                       imageCount: 2, hasBody: true,
                       agent: RemoteTaskAgent(state: .needsInput, title: "Claude Opus", checkout: "daily-rewards",
                                              terminalId: DemoIDs.rewards)),
            RemoteTask(source: Self.sourceID, id: "WP-14", title: "Tile drop animation stutters on iPhone SE", status: .todo,
                       priority: "urgent", labels: ["bug", "perf"], assignee: Self.ada, project: game, updatedAt: ago(3),
                       hasBody: true),
            RemoteTask(source: Self.sourceID, id: "LM-7", title: "Relay reconnect backoff", status: .inReview,
                       priority: "medium", labels: ["relay"], assignee: Self.me, project: lumi, updatedAt: ago(5),
                       hasBody: true,
                       agent: RemoteTaskAgent(state: .submitted, title: "Claude Sonnet", checkout: "Lumi",
                                              terminalId: DemoIDs.relay,
                                              summary: "Added exponential backoff with jitter (max 30 s) and a test for the reconnect loop.")),
            RemoteTask(source: Self.sourceID, id: "WP-15", title: "Localize the shop", status: .todo,
                       priority: "low", project: game, updatedAt: ago(20)),
            RemoteTask(source: Self.sourceID, id: "LM-5", title: "Fix flaky orchestrator test", status: .todo,
                       priority: "medium", labels: ["ci"], assignee: Self.linus, project: lumi, updatedAt: ago(26),
                       needsAttention: true),
            RemoteTask(source: Self.sourceID, id: "WP-9", title: "Hint button cooldown", status: .done,
                       assignee: Self.me, project: game, updatedAt: ago(48)),
        ]
        bodies = [
            "WP-12": "Show a 7-day calendar with the current streak.\n\n- Claim button glows on the current day\n- Missed days are greyed out",
            "WP-14": "Profiling shows a spike in `TileDropAnimator.update`. Repro: level 12 on iPhone SE (3rd gen).",
            "LM-7": "The relay client retries immediately after a drop. Add exponential backoff with jitter.",
        ]
    }

    var snapshot: TasksSnapshot {
        TasksSnapshot(
            sources: [TaskSourceSummary(
                id: Self.sourceID, name: "Team Board", kind: "custom", phase: .ready,
                capabilities: ["create", "delete", "users"],
                fields: ["body": "rw", "priority": "rw", "labels": "r", "assignee": "rw", "project": "r", "images": "r"],
                canAssign: true, me: Self.me, users: [Self.me, Self.ada, Self.linus]
            )],
            tasks: tasks
        )
    }

    func detail(_ id: String) -> [String: String]? {
        guard let task = tasks.first(where: { $0.id == id }) else { return nil }
        var data = ["prompt": "Work on task \(task.id): \(task.title)\n\nWhen the work is complete and verified (builds, tests), call the `submit_for_review` tool from the lumi MCP server with a short summary of what you changed."]
        if let body = bodies[id] { data["body"] = body }
        return data
    }

    mutating func move(_ id: String, to status: RemoteTaskStatus) -> Bool {
        update(id) { $0.status = status }
    }

    mutating func assign(_ id: String, to userID: String?) -> Bool {
        let user = [Self.me, Self.ada, Self.linus].first { $0.id == userID }
        guard userID == nil || user != nil else { return false }
        return update(id) { $0.assignee = user }
    }

    mutating func create(title: String, status: RemoteTaskStatus, nowMs: Double) -> String {
        nextID += 1
        let id = "WP-\(nextID)"
        tasks.insert(RemoteTask(source: Self.sourceID, id: id, title: title, status: status, updatedAt: nowMs), at: 0)
        return id
    }

    /// Starting links the task to the live demo session (`tiles`).
    mutating func start(_ id: String, model: String?) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].agent?.state.isActive != true else { return false }
        let old = tasks[index]
        tasks[index] = RemoteTask(
            source: old.source, id: old.id, title: old.title, status: .inProgress, priority: old.priority,
            labels: old.labels, assignee: Self.me, project: old.project, updatedAt: old.updatedAt,
            imageCount: old.imageCount, hasBody: old.hasBody, url: old.url,
            agent: RemoteTaskAgent(state: .working, title: model.map { "Claude \($0.capitalized)" } ?? "Claude",
                                   checkout: "task/\(old.id.lowercased())", terminalId: DemoIDs.tiles)
        )
        return true
    }

    private mutating func update(_ id: String, _ change: (inout RemoteTask) -> Void) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }
        change(&tasks[index])
        return true
    }
}
