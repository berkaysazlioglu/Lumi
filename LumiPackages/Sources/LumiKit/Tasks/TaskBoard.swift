import Foundation

/// Board/List filtresi.
public struct TaskFilter: Sendable, Hashable {
    /// Atanan filtresi: hepsi, bana atananlar, atanmamışlar ya da belirli kişi.
    public enum Assignee: Sendable, Hashable {
        case anyone
        case me
        case unassigned
        case user(id: String)
    }

    public var query: String
    public var source: TaskSourceID?
    public var projectKey: String?
    public var assignee: Assignee

    public init(
        query: String = "",
        source: TaskSourceID? = nil,
        projectKey: String? = nil,
        assignee: Assignee = .anyone
    ) {
        self.query = query
        self.source = source
        self.projectKey = projectKey
        self.assignee = assignee
    }

    public var isActive: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty || projectKey != nil || assignee != .anyone
    }

    /// `me`: kaynağın token sahibi; kaynak başına farklı olabilir.
    public func matches(_ entry: TaskEntry, me: TaskUser?) -> Bool {
        if let source, entry.source != source { return false }
        if let projectKey, entry.item.project?.key != projectKey { return false }
        switch assignee {
        case .anyone: break
        case .me:
            guard let me, entry.item.assignee?.id == me.id else { return false }
        case .unassigned:
            if entry.item.assignee != nil { return false }
        case .user(let id):
            if entry.item.assignee?.id != id { return false }
        }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        let item = entry.item
        return item.title.localizedCaseInsensitiveContains(needle)
            || item.id.localizedCaseInsensitiveContains(needle)
            || item.labels.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

/// Saf kolonlama: filtrelenmiş task'leri dört duruma böler ve sıralar.
public enum TaskBoard {
    /// Done kolonunun varsayılan üst sınırı (plan: "Done kolonu son 20").
    public static let doneLimit = 20

    public struct Column: Sendable, Hashable, Identifiable {
        public let status: TaskStatus
        public let entries: [TaskEntry]
        /// Sınır yüzünden gösterilmeyen task sayısı (yalnız Done'da).
        public let hiddenCount: Int

        public var id: TaskStatus { status }
        public var totalCount: Int { entries.count + hiddenCount }
    }

    /// Kolon içi sıra: dikkat isteyen en üstte, sonra yüksek öncelik, sonra
    /// en son güncellenen. Done'da yalnız güncellenme (en yeni üstte).
    public static func columns(
        _ entries: [TaskEntry],
        filter: TaskFilter,
        me: (TaskSourceID) -> TaskUser?,
        showAllDone: Bool = false
    ) -> [Column] {
        let visible = entries.filter { filter.matches($0, me: me($0.source)) }
        let grouped = Dictionary(grouping: visible, by: \.item.status)
        return TaskStatus.allCases.map { status in
            let sorted = sort(grouped[status] ?? [], status: status)
            guard status == .done, !showAllDone, sorted.count > doneLimit else {
                return Column(status: status, entries: sorted, hiddenCount: 0)
            }
            return Column(status: status, entries: Array(sorted.prefix(doneLimit)), hiddenCount: sorted.count - doneLimit)
        }
    }

    /// List görünümü: tek düz liste, durum sırasına göre gruplanmış.
    public static func rows(
        _ entries: [TaskEntry],
        filter: TaskFilter,
        me: (TaskSourceID) -> TaskUser?
    ) -> [TaskEntry] {
        columns(entries, filter: filter, me: me, showAllDone: true).flatMap(\.entries)
    }

    static func sort(_ entries: [TaskEntry], status: TaskStatus) -> [TaskEntry] {
        entries.sorted { lhs, rhs in
            let left = lhs.item
            let right = rhs.item
            if status != .done {
                if left.needsAttention != right.needsAttention { return left.needsAttention }
                let leftPriority = left.priority ?? .none
                let rightPriority = right.priority ?? .none
                if leftPriority != rightPriority { return leftPriority > rightPriority }
            }
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id < right.id
        }
    }
}

/// Atama seçicisinin sırası (kullanıcı kararı 5): `You` en üstte, sonra
/// diğerleri ada göre.
public enum TaskUserOrdering {
    public struct Option: Sendable, Hashable, Identifiable {
        public let user: TaskUser
        public let isMe: Bool

        public var id: String { user.id }
        public var title: String { isMe ? "You (\(user.name))" : user.name }
    }

    public static func options(users: [TaskUser], me: TaskUser?) -> [Option] {
        var seen = Set<String>()
        var result: [Option] = []
        if let me {
            result.append(Option(user: me, isMe: true))
            seen.insert(me.id)
        }
        let others = users
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        result.append(contentsOf: others.map { Option(user: $0, isMe: false) })
        return result
    }
}
