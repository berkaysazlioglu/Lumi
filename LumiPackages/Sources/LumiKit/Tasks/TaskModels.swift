import Foundation

/// Bir task'in dört sabit durumu (Tasks planı, kullanıcı kararı 1).
///
/// Ham değerler protokolün tel değerleridir (`in_progress`, `in_review`);
/// sıra Board'un soldan sağa kolon sırasıdır.
public enum TaskStatus: String, CaseIterable, Sendable, Hashable {
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
}

/// Opsiyonel öncelik alanı. `none` "öncelik verilmemiş" demektir; alanın hiç
/// desteklenmemesi ayrı bir şeydir ve `TaskSourceInfo.fields`'ta yazar.
public enum TaskPriority: String, CaseIterable, Sendable, Hashable, Comparable {
    case none
    case low
    case medium
    case high
    case urgent

    public var title: String {
        switch self {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }

    private var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Kaynağın bir kullanıcısı (atama ve filtre). Kimlik kaynak içinde tekildir.
public struct TaskUser: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let email: String?

    public init(id: String, name: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }

    /// Avatar baş harfleri: ilk iki kelimenin ilk harfi, tek kelimede ilk iki harf.
    public var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count >= 2 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

/// Task'in Lumi projesiyle eşleşme ipucu (plan: "Proje eşleşmesi").
public struct TaskProjectRef: Sendable, Hashable {
    public let key: String
    public let name: String?
    /// Git remote adresi — Lumi projesinin `origin`'iyle eşleştirilir (Faz 3).
    public let repo: String?

    public init(key: String, name: String? = nil, repo: String? = nil) {
        self.key = key
        self.name = name
        self.repo = repo
    }

    public var displayName: String { name ?? key }
}

/// Adapter'dan bağımsız ortak task modeli — UI yalnız bunu görür.
///
/// Zorunlu alanlar `id`, `title`, `status`, `updatedAt`; gerisi kaynak
/// desteklemiyorsa boştur ve UI'da hiç görünmez.
public struct TaskItem: Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var status: TaskStatus
    public var updatedAt: Date
    public var createdAt: Date?
    public var body: String?
    public var project: TaskProjectRef?
    public var priority: TaskPriority?
    public var labels: [String]
    public var assignee: TaskUser?
    public var dueDate: Date?
    public var url: URL?
    /// Sunucu dört durumdan biri olmayan bir değer döndürdü (ya da zorunlu bir
    /// alan bozuktu): task atılmaz, `Needs attention` rozetiyle Todo'da durur.
    public var needsAttention: Bool

    public init(
        id: String,
        title: String,
        status: TaskStatus,
        updatedAt: Date,
        createdAt: Date? = nil,
        body: String? = nil,
        project: TaskProjectRef? = nil,
        priority: TaskPriority? = nil,
        labels: [String] = [],
        assignee: TaskUser? = nil,
        dueDate: Date? = nil,
        url: URL? = nil,
        needsAttention: Bool = false
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.body = body
        self.project = project
        self.priority = priority
        self.labels = labels
        self.assignee = assignee
        self.dueDate = dueDate
        self.url = url
        self.needsAttention = needsAttention
    }
}

/// Kısmi güncelleme — yalnız dolu alanlar gönderilir (protokolde `PATCH`).
public struct TaskPatch: Sendable, Hashable {
    /// Atamanın üç hâli: dokunma (`nil`), birine ata, boşalt.
    public enum AssigneeChange: Sendable, Hashable {
        case assign(TaskUser)
        case unassign
    }

    public var status: TaskStatus?
    public var title: String?
    public var priority: TaskPriority?
    public var assignee: AssigneeChange?

    public init(
        status: TaskStatus? = nil,
        title: String? = nil,
        priority: TaskPriority? = nil,
        assignee: AssigneeChange? = nil
    ) {
        self.status = status
        self.title = title
        self.priority = priority
        self.assignee = assignee
    }

    /// Yamanın yerel kopyaya uygulanmış hâli — iyimser güncelleme için.
    public func applied(to item: TaskItem, now: Date) -> TaskItem {
        var copy = item
        if let status {
            copy.status = status
            copy.needsAttention = false
        }
        if let title { copy.title = title }
        if let priority { copy.priority = priority }
        switch assignee {
        case .assign(let user): copy.assignee = user
        case .unassign: copy.assignee = nil
        case nil: break
        }
        copy.updatedAt = now
        return copy
    }
}

/// Yeni task taslağı (capability `create`).
public struct TaskDraft: Sendable, Hashable {
    public var title: String
    public var body: String?
    public var status: TaskStatus
    public var projectKey: String?
    public var priority: TaskPriority?
    public var assignee: TaskUser?

    public init(
        title: String,
        body: String? = nil,
        status: TaskStatus = .todo,
        projectKey: String? = nil,
        priority: TaskPriority? = nil,
        assignee: TaskUser? = nil
    ) {
        self.title = title
        self.body = body
        self.status = status
        self.projectKey = projectKey
        self.priority = priority
        self.assignee = assignee
    }
}
