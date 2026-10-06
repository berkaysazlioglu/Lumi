import Foundation

public struct AgentRowData: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let provider: String?
    public let badge: Badge
    public let activity: AgentActivity
    public let lastActivityAt: Double?
    public let needsAttention: Bool
}

public struct CheckoutRowData: Sendable, Equatable, Identifiable {
    public let node: CheckoutNode
    public let agents: [AgentRowData]
    public var id: String { node.path }
}

public struct ProjectRowData: Sendable, Equatable, Identifiable {
    public let node: ProjectNode
    public let checkouts: [CheckoutRowData]
    public var id: String { node.path }
}

public struct OtherGroupRowData: Sendable, Equatable, Identifiable {
    public let node: OtherGroupNode
    public let agents: [AgentRowData]
    public var id: String { node.path }
}

/// Attention rule (Mac `TerminalAttention` parity, decision 77): an unselected
/// terminal whose turn closed unseen / is awaiting a decision. `waiting-seen`
/// is NOT re-highlighted.
public func terminalNeedsAttention(status: String, isSelected: Bool) -> Bool {
    guard !isSelected else { return false }
    return status == "waiting-unseen" || status == "waiting-focused"
}

/// Builds the view-ready tree by joining each checkout's `agentIds` against the
/// live `sessions` map. Order comes from `agentIds` (the Mac already sorted);
/// ids not yet present in `sessions` are skipped (subscribe/broadcast race guard).
public func assembleProjectTree(snapshot: ProjectsSnapshot,
                                sessions: [SessionMeta],
                                selectedId: String?) -> [ProjectRowData] {
    let join = AgentJoin(sessions: sessions, selectedId: selectedId)
    return snapshot.projects.map { project in
        ProjectRowData(node: project, checkouts: project.checkouts.map { checkout in
            CheckoutRowData(node: checkout, agents: join.rows(checkout.agentIds))
        })
    }
}

/// Projects ▸ Other, joined against `sessions` the same way. Groups whose
/// agents are not in `sessions` yet are dropped (nothing to show).
public func assembleOtherGroups(snapshot: ProjectsSnapshot,
                                sessions: [SessionMeta],
                                selectedId: String?) -> [OtherGroupRowData] {
    let join = AgentJoin(sessions: sessions, selectedId: selectedId)
    return snapshot.others.compactMap { group in
        let agents = join.rows(group.agentIds)
        return agents.isEmpty ? nil : OtherGroupRowData(node: group, agents: agents)
    }
}

private struct AgentJoin {
    let byId: [String: SessionMeta]
    let selectedId: String?

    init(sessions: [SessionMeta], selectedId: String?) {
        byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.selectedId = selectedId
    }

    func rows(_ ids: [String]) -> [AgentRowData] {
        ids.compactMap { id -> AgentRowData? in
            guard let s = byId[id] else { return nil }
            return AgentRowData(
                id: s.id,
                title: (s.title?.isEmpty == false ? s.title! : s.repoName),
                provider: s.provider,
                badge: s.badge,
                activity: s.activity,
                lastActivityAt: s.lastActivityAt,
                needsAttention: terminalNeedsAttention(status: s.status, isSelected: s.id == selectedId))
        }
    }
}

/// Compact relative-time label ("now" / "5m" / "3h" / "2d"). All arithmetic in ms.
public enum PhoneRelativeTime {
    public static func shortLabel(_ epochMs: Double?, now: Double) -> String {
        guard let epochMs else { return "" }
        let secs = max(0, (now - epochMs) / 1000)
        if secs < 45 { return "now" }
        let mins = Int((secs / 60).rounded())
        if mins < 60 { return "\(mins)m" }
        let hrs = mins / 60
        if hrs < 24 { return "\(hrs)h" }
        return "\(hrs / 24)d"
    }
}
