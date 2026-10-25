import Foundation

/// Bir adapter'ın hataları — UI bunlardan kaynağın durumunu türetir
/// (`Reconnect`, `Offline`, `Unsupported`…).
public enum TaskProviderError: Error, Sendable, Hashable, LocalizedError {
    /// 401 — token geçersiz ya da iptal edilmiş.
    case unauthorized
    /// 404 — task (artık) yok.
    case notFound
    /// Kaynak bu işlemi desteklemiyor (capability yok).
    case unsupported(String)
    /// Sunucu başka bir protokol sürümü konuşuyor.
    case unsupportedVersion(Int)
    /// 409 — task sunucuda değişmiş.
    case conflict
    /// Ağa ulaşılamadı / zaman aşımı.
    case unreachable(String)
    /// Sunucu beklenmeyen bir yanıt verdi (geçersiz JSON, 5xx…).
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "The token was rejected (401). Reconnect with a new token."
        case .notFound: "The task no longer exists on the server."
        case .unsupported(let what): "This source doesn't support \(what)."
        case .unsupportedVersion(let version):
            "This server speaks lumi-tasks v\(version); this Lumi supports up to v\(TaskSourceInfo.supportedVersion)."
        case .conflict: "The task changed on the server."
        case .unreachable(let detail): "Couldn't reach the server: \(detail)"
        case .invalidResponse(let detail): "Unexpected response from the server: \(detail)"
        }
    }
}

/// Bir task kaynağının adapter'ı (plan: "Lumi tarafı mimari").
///
/// UI ve store hangi adapter'la konuştuklarını bilmez. Desteklenmeyen bir
/// yeteneğin metodu `TaskProviderError.unsupported` fırlatır — ama çağıran
/// taraf zaten önce `TaskSourceInfo`'ya bakar.
public protocol TaskProviding: Sendable {
    func discover() async throws -> TaskSourceInfo
    /// `since` nil ise tam liste; doluysa önceki listenin `syncToken`'ı ile
    /// yalnız o andan beri değişenler istenir (bkz. `TaskListing`).
    func listTasks(since syncToken: String?) async throws -> TaskListing
    func update(taskID: String, patch: TaskPatch) async throws -> TaskItem
    func create(_ draft: TaskDraft) async throws -> TaskItem
    func delete(taskID: String) async throws
    func listUsers() async throws -> [TaskUser]
    func listProjects() async throws -> [TaskProjectRef]
    /// Görsel isteğine eklenecek yetki başlığı (bkz. varsayılan uygulama).
    func authorization(for url: URL) -> String?
}

extension TaskProviding {
    /// Tam liste (Verify ve testler).
    public func listTasks() async throws -> [TaskItem] {
        try await listTasks(since: nil).tasks
    }
}

/// `GET /tasks` cevabı (Lumi Tasks Protocol v1, artımlı senkron).
///
/// Tam listede `allIDs` nil'dir. Delta cevabında `tasks` yalnız değişenlerdir,
/// `allIDs` kaynakta şu an var olan TÜM task kimlikleridir — silinenler
/// buradan çıkarılır, sunucu mezar taşı tutmak zorunda kalmaz. `since`'i
/// tanımayan sunucu onu yok sayıp `ids`'siz tam liste döner; bu yüzden eski
/// sunucular olduğu gibi çalışır.
public struct TaskListing: Sendable, Equatable {
    public var tasks: [TaskItem]
    public var allIDs: [String]?
    /// Bir sonraki tazelemede `since` olarak geri gönderilecek opak değer.
    public var syncToken: String?

    public init(tasks: [TaskItem], allIDs: [String]? = nil, syncToken: String? = nil) {
        self.tasks = tasks
        self.allIDs = allIDs
        self.syncToken = syncToken
    }

    public var isDelta: Bool { allIDs != nil }
}

/// Kaynak → adapter. Canlı uygulaması LumiServices'te; token Faz 2'de
/// Keychain'den okunup buraya verilir.
public protocol TaskProviderMaking: Sendable {
    func makeProvider(for source: TaskSource, token: String?) -> any TaskProviding
}
