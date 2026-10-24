import Foundation

/// Bağlı bir task kaynağının kimliği (UUID string).
public struct TaskSourceID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static func make() -> TaskSourceID { TaskSourceID(UUID().uuidString) }
}

/// Bir kaynağı Lumi'nin ortak modeline çeviren adapter türü.
///
/// v1'de tek gerçek adapter `custom`dur (Lumi Tasks Protocol); `demo` bellek
/// içi örnek veridir. Hazır servis adapter'ları (GitHub, Linear) sonra gelir.
public enum TaskProviderKind: String, CaseIterable, Sendable, Hashable {
    case custom
    case demo
    case github
    case linear

    public var title: String {
        switch self {
        case .custom: "Custom (Lumi Tasks API)"
        case .demo: "Demo data"
        case .github: "GitHub Issues"
        case .linear: "Linear"
        }
    }

    public var subtitle: String {
        switch self {
        case .custom: "Your own server — Heroku, Railway, anywhere"
        case .demo: "Sample tasks kept in memory, to try the board"
        case .github, .linear: "Coming soon"
        }
    }

    /// Bağlama sheet'inde seçilebilir mi (henüz yazılmamış adapter'lar soluk).
    public var isAvailable: Bool {
        switch self {
        case .custom, .demo: true
        case .github, .linear: false
        }
    }

    /// Bağlanırken adres + token isteyen adapter.
    public var needsEndpoint: Bool { self == .custom }
}

/// Kaynağın task'lerinden üretilen prompt'ların ön eki ve son eki (karar 137
/// eki): ör. "Bu repo'da Swift 6 strict concurrency kullan" ya da "Bitince
/// CHANGELOG'u güncelle". Ajan prompt'u da `Copy as Prompt` da bununla sarılır.
public struct TaskPromptTemplate: Sendable, Hashable {
    public var prefix: String
    public var suffix: String

    public init(prefix: String = "", suffix: String = "") {
        self.prefix = prefix
        self.suffix = suffix
    }

    public var isEmpty: Bool {
        prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Boş parçalar atlanır; parçalar arasında bir boş satır.
    public func wrap(_ core: String) -> String {
        [prefix, core, suffix]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

/// Kullanıcının bağladığı tek bir kaynak. Token burada DURMAZ — Keychain'dedir
/// (Faz 2); adapter kurulurken ayrıca verilir.
public struct TaskSource: Sendable, Hashable, Identifiable {
    public let id: TaskSourceID
    public var name: String
    public let kind: TaskProviderKind
    public var baseURL: String?
    public var promptTemplate: TaskPromptTemplate

    public init(
        id: TaskSourceID = .make(), name: String, kind: TaskProviderKind, baseURL: String? = nil,
        promptTemplate: TaskPromptTemplate = TaskPromptTemplate()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.promptTemplate = promptTemplate
    }
}

/// Kaynak içindeki tek bir task'in Lumi genelindeki kimliği.
public struct TaskKey: Hashable, Sendable {
    public let source: TaskSourceID
    public let id: String

    public init(source: TaskSourceID, id: String) {
        self.source = source
        self.id = id
    }

    /// Sürükle-bırak yükü: `<sourceID>|<taskID>`. Task kimliği `|` içerebilir,
    /// bu yüzden ilk ayraçta bölünür (kaynak kimliği UUID'dir).
    public var transferValue: String { "\(source.rawValue)|\(id)" }

    public init?(transferValue: String) {
        guard let separator = transferValue.firstIndex(of: "|") else { return nil }
        let source = String(transferValue[..<separator])
        let id = String(transferValue[transferValue.index(after: separator)...])
        guard !source.isEmpty, !id.isEmpty else { return nil }
        self.init(source: TaskSourceID(source), id: id)
    }
}

/// Board'daki tek satır: task + ait olduğu kaynak.
public struct TaskEntry: Sendable, Hashable, Identifiable {
    public let source: TaskSourceID
    public var item: TaskItem

    public init(source: TaskSourceID, item: TaskItem) {
        self.source = source
        self.item = item
    }

    public var key: TaskKey { TaskKey(source: source, id: item.id) }
    public var id: TaskKey { key }
}
