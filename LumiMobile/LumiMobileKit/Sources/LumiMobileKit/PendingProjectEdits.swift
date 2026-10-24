import Foundation

/// Phone-side project edits (decision 132) shown before the Mac confirms them.
/// The Mac stays the source of truth: an edit is dropped once a `projects`
/// snapshot reflects it, once a snapshot arrives after the Mac confirmed it,
/// or when the Mac rejects it.
public struct PendingProjectEdits: Sendable, Equatable {
    struct Edit<Value: Sendable & Equatable>: Sendable, Equatable {
        let value: Value
        let commandId: String
        var isConfirmed = false
    }

    private(set) var order: Edit<[String]>?
    private(set) var appearances: [String: Edit<ProjectAppearance>] = [:]

    public init() {}

    public var isEmpty: Bool { order == nil && appearances.isEmpty }

    mutating func setOrder(_ paths: [String], commandId: String) {
        order = Edit(value: paths, commandId: commandId)
    }

    mutating func setAppearance(_ appearance: ProjectAppearance, for path: String, commandId: String) {
        appearances[path] = Edit(value: appearance, commandId: commandId)
    }

    /// The snapshot as the phone should show it: pending order first, pending
    /// appearances over the Mac's.
    public func applied(to snapshot: ProjectsSnapshot) -> ProjectsSnapshot {
        guard !isEmpty else { return snapshot }
        var projects = snapshot.projects.map { project in
            guard let edit = appearances[project.path] else { return project }
            return ProjectNode(name: project.name, path: project.path,
                               checkouts: project.checkouts, appearance: edit.value)
        }
        if let order {
            let rank = Dictionary(order.value.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            // Stable: projects the order doesn't know (added meanwhile) keep their place at the end.
            projects = projects.enumerated().sorted { lhs, rhs in
                let l = rank[lhs.element.path] ?? order.value.count + lhs.offset
                let r = rank[rhs.element.path] ?? order.value.count + rhs.offset
                return l < r
            }.map(\.element)
        }
        return ProjectsSnapshot(projects: projects, others: snapshot.others, addable: snapshot.addable,
                                looseLocations: snapshot.looseLocations, display: snapshot.display)
    }

    /// A fresh snapshot from the Mac: drops the edits it already shows and the
    /// ones the Mac confirmed earlier (this snapshot is then the truth).
    mutating func reconcile(with snapshot: ProjectsSnapshot) {
        if let edit = order {
            let shown = snapshot.projects.map(\.path)
            if edit.isConfirmed || shown == edit.value.filter(Set(shown).contains) { order = nil }
        }
        let byPath = Dictionary(snapshot.projects.map { ($0.path, $0.appearance) },
                                uniquingKeysWith: { first, _ in first })
        appearances = appearances.filter { path, edit in
            !edit.isConfirmed && byPath[path] != edit.value && byPath[path] != nil
        }
    }

    /// The Mac's answer to an edit command: success keeps the edit until the
    /// next snapshot, failure drops it (the Mac's state shows again).
    mutating func resolve(commandId: String, ok: Bool) {
        if order?.commandId == commandId {
            if ok { order?.isConfirmed = true } else { order = nil }
        }
        for (path, edit) in appearances where edit.commandId == commandId {
            if ok { appearances[path]?.isConfirmed = true } else { appearances[path] = nil }
        }
    }
}
