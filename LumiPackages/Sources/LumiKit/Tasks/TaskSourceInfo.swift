import Foundation

/// Kaynağın beyan ettiği opsiyonel yetenekler (protokolde `capabilities`).
public enum TaskCapability: String, CaseIterable, Sendable, Hashable {
    case create
    case delete
    /// `GET /users` — atama seçicisi ve atanan filtresi.
    case users
    /// `GET /projects` — oluşturmada proje seçimi.
    case projects
    /// Lumi'nin ajan bağlantısını task üstünde saklama (Faz 3).
    case lumiMetadata

    public var title: String {
        switch self {
        case .create: "Create tasks"
        case .delete: "Delete tasks"
        case .users: "User list"
        case .projects: "Project list"
        case .lumiMetadata: "Lumi metadata"
        }
    }
}

/// Opsiyonel task alanları (protokolde `fields`). Zorunlu alanlar (`id`,
/// `title`, `status`, `updatedAt`) burada yer almaz — her kaynakta vardır.
public enum TaskField: String, CaseIterable, Sendable, Hashable {
    case body
    case project
    case priority
    case labels
    case assignee
    case dueDate
    case url

    public var title: String {
        switch self {
        case .body: "Description"
        case .project: "Project"
        case .priority: "Priority"
        case .labels: "Labels"
        case .assignee: "Assignee"
        case .dueDate: "Due date"
        case .url: "Link"
        }
    }
}

/// Bir alanın erişimi: yalnız okunur (`r`) ya da yazılabilir (`rw`).
public enum TaskFieldAccess: String, Sendable, Hashable {
    case read = "r"
    case readWrite = "rw"
}

/// Discovery'nin sonucu: kaynağın kim olduğu ve ne desteklediği.
///
/// Planın tek ilkesi buradan uygulanır: **UI, kaynağın beyan ettiği kadardır.**
/// Görünümler alan/yetenek sorusunu yalnız bu tipe sorar.
public struct TaskSourceInfo: Sendable, Hashable {
    /// Lumi'nin konuşabildiği en yüksek protokol sürümü.
    public static let supportedVersion = 1

    public let name: String?
    public let version: Int
    public var capabilities: Set<TaskCapability>
    public var fields: [TaskField: TaskFieldAccess]
    /// Token'ın sahibi — atama seçicisinde `You`.
    public let me: TaskUser?

    public init(
        name: String? = nil,
        version: Int = TaskSourceInfo.supportedVersion,
        capabilities: Set<TaskCapability> = [],
        fields: [TaskField: TaskFieldAccess] = [:],
        me: TaskUser? = nil
    ) {
        self.name = name
        self.version = version
        self.capabilities = capabilities
        self.fields = fields
        self.me = me
    }

    public func supports(_ capability: TaskCapability) -> Bool {
        capabilities.contains(capability)
    }

    public func canRead(_ field: TaskField) -> Bool { fields[field] != nil }

    public func canWrite(_ field: TaskField) -> Bool { fields[field] == .readWrite }

    public var isVersionSupported: Bool { version <= Self.supportedVersion }

    /// Atama yapılabilir mi: alan yazılabilir olmalı ve seçicide en az bir
    /// aday bulunmalı (`users` listesi ya da en azından `me`).
    public var canAssign: Bool {
        canWrite(.assignee) && (supports(.users) || me != nil)
    }

    /// Demo kaynağın "X yoksa" anahtarları için: beyanın bir kısmı kapatılmış
    /// kopyası. Kapatılan yetenek/alan yalnız düşer, yenisi eklenmez.
    public func masked(capabilities hidden: Set<TaskCapability>, fields hiddenFields: Set<TaskField>) -> TaskSourceInfo {
        var copy = self
        copy.capabilities.subtract(hidden)
        for field in hiddenFields { copy.fields[field] = nil }
        return copy
    }
}
