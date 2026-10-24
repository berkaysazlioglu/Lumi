import Foundation
import LumiKit
import LumiState

/// Telefona giden `tasks` anlık görüntüsü (karar 137 mobil ek) — saf.
///
/// Gövde (`body`) ve görsel adresleri girmez: boyut. Telefon detayı
/// `task_detail` ile ister. Görüntü relay'in frame sınırına karşı
/// `budget` baytına oturtulur: sığmazsa en eski Done'lar kırpılır.
@MainActor
enum RemoteTasksSnapshot {
    /// Relay'in 1 MB frame sınırının altında güvenli pay (karar 130 ile aynı).
    static let budget = 700_000

    static func payload(_ store: TasksStore, now: Date = Date(), budget: Int = budget) -> [String: Any] {
        let sources = store.sources.map(source)
        var tasks = store.entries.map { task($0, store: store) }
        var truncated = 0
        var object: [String: Any] = ["sources": sources, "tasks": tasks, "generatedAt": milliseconds(now), "truncatedDone": 0]
        // En eski Done'dan başlayarak bütçeye sığdır.
        let oldestDoneFirst = store.entries.enumerated()
            .filter { $0.element.item.status == .done }
            .sorted { $0.element.item.updatedAt < $1.element.item.updatedAt }
            .map { $0.element.key }
        var removable = oldestDoneFirst[...]
        while size(of: object) > budget, let next = removable.popFirst() {
            tasks.removeAll { ($0["source"] as? String) == next.source.rawValue && ($0["id"] as? String) == next.id }
            truncated += 1
            object["tasks"] = tasks
            object["truncatedDone"] = truncated
        }
        return object
    }

    static func data(_ store: TasksStore, now: Date = Date()) -> Data? {
        try? JSONSerialization.data(withJSONObject: payload(store, now: now), options: .sortedKeys)
    }

    // MARK: - Parçalar

    private static func source(_ state: TasksStore.SourceState) -> [String: Any] {
        var entry: [String: Any] = [
            "id": state.id.rawValue,
            "name": state.source.name,
            "kind": state.source.kind.rawValue,
            "phase": phaseName(state.phase),
            "users": state.users.map(user),
        ]
        if let message = phaseMessage(state.phase) { entry["phaseMessage"] = message }
        if let lastUpdated = state.lastUpdated { entry["lastUpdated"] = milliseconds(lastUpdated) }
        if let info = state.info {
            entry["capabilities"] = info.capabilities.map(\.rawValue).sorted()
            entry["fields"] = info.fields.mapValues(\.rawValue).reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value }
            entry["canAssign"] = info.canAssign
            if let me = info.me { entry["me"] = user(me) }
        }
        return entry
    }

    private static func task(_ entry: TaskEntry, store: TasksStore) -> [String: Any] {
        let item = entry.item
        var task: [String: Any] = [
            "source": entry.source.rawValue,
            "id": item.id,
            "title": item.title,
            "status": item.status.rawValue,
            "updatedAt": milliseconds(item.updatedAt),
            "needsAttention": item.needsAttention,
            "labels": item.labels,
            "imageCount": item.images.count,
            "hasBody": !(item.body ?? "").isEmpty,
        ]
        if let priority = item.priority { task["priority"] = priority.rawValue }
        if let assignee = item.assignee { task["assignee"] = user(assignee) }
        if let project = item.project {
            var ref: [String: Any] = ["key": project.key]
            if let name = project.name { ref["name"] = name }
            task["project"] = ref
        }
        if let url = item.url { task["url"] = url.absoluteString }
        if let link = store.agentLink(for: entry.key) { task["agent"] = agent(link) }
        return task
    }

    private static func agent(_ link: TaskAgentLink) -> [String: Any] {
        var agent: [String: Any] = [
            "state": stateName(link.state),
            "title": link.agent.title,
            "checkout": link.checkout.label,
            "reattached": link.isReattached,
            "startedAt": milliseconds(link.startedAt),
        ]
        // Telefonun oturum kimliği terminal kimliğidir (sessions payload'ı).
        if let terminal = link.terminalID { agent["terminalId"] = terminal.description }
        if case .submitted(let summary) = link.state { agent["summary"] = summary }
        return agent
    }

    private static func user(_ user: TaskUser) -> [String: Any] {
        ["id": user.id, "name": user.name]
    }

    static func stateName(_ state: TaskAgentState) -> String {
        switch state {
        case .starting: "starting"
        case .working: "working"
        case .needsInput: "needsInput"
        case .idle: "idle"
        case .submitted: "submitted"
        case .exited: "exited"
        }
    }

    static func phaseName(_ phase: TasksStore.Phase) -> String {
        switch phase {
        case .loading: "loading"
        case .ready: "ready"
        case .offline: "offline"
        case .failing: "failing"
        case .reconnect: "reconnect"
        case .unsupported: "unsupported"
        }
    }

    private static func phaseMessage(_ phase: TasksStore.Phase) -> String? {
        switch phase {
        case .offline(let message), .failing(let message), .unsupported(let message): message
        case .reconnect: "The server rejected the token."
        case .loading, .ready: nil
        }
    }

    private static func milliseconds(_ date: Date) -> Double {
        (date.timeIntervalSince1970 * 1000).rounded()
    }

    private static func size(of object: [String: Any]) -> Int {
        (try? JSONSerialization.data(withJSONObject: object))?.count ?? 0
    }
}
