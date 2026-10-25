import Foundation

/// Paylaşılan oturumları yükleyen kişi — kimliğini sunucu token'dan belirler
/// (Lumi Sessions Protocol v1, karar 138).
public struct SharedSessionUploader: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Sunucudaki bir oturumun liste özeti. Paket gövdesi listede gelmez;
/// içe aktarırken ayrıca indirilir.
public struct SharedSession: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// Yükleyenin verdiği düz proje adı (yol, dal, kaynak denetimi değil).
    public let project: String
    public let provider: AgentProvider?
    public let uploader: SharedSessionUploader
    public let uploadedAt: Date
    public let sizeBytes: Int?

    public init(
        id: String, title: String, project: String, provider: AgentProvider?,
        uploader: SharedSessionUploader, uploadedAt: Date, sizeBytes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.provider = provider
        self.uploader = uploader
        self.uploadedAt = uploadedAt
        self.sizeBytes = sizeBytes
    }
}

/// `GET /lumi/sessions/v1` — discovery. `me` zorunludur: "kendi
/// yüklediklerim" ve silme düğmesi ona bakar.
public struct SessionServerInfo: Sendable, Hashable {
    public let name: String?
    public let me: SharedSessionUploader
    public let maxUploadBytes: Int?

    public init(name: String?, me: SharedSessionUploader, maxUploadBytes: Int? = nil) {
        self.name = name
        self.me = me
        self.maxUploadBytes = maxUploadBytes
    }
}

/// Bağlı oturum sunucusunun `config.json` kaydı (additive `sessionServer`).
/// Token burada DEĞİL, Keychain'dedir (`com.lumi.sessions` / `id`).
public struct SessionServer: Sendable, Hashable {
    public let id: String
    public var name: String
    public var baseURL: String

    public init(id: String, name: String, baseURL: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}

/// `POST /lumi/sessions/v1/sessions` gövdesi. `archive`, karar 52'nin
/// `.lumisession.json` paketinin baytlarıdır (kişisel kayıtlar ayıklanmış).
public struct SharedSessionUpload: Sendable {
    public let title: String
    public let project: String
    public let provider: AgentProvider
    public let archive: Data

    public init(title: String, project: String, provider: AgentProvider, archive: Data) {
        self.title = title
        self.project = project
        self.provider = provider
        self.archive = archive
    }
}

/// Lumi Sessions Protocol v1 istemcisi. Canlıda HTTP, testlerde fake.
public protocol SessionSharing: Sendable {
    func discover() async throws -> SessionServerInfo
    func listSessions() async throws -> [SharedSession]
    /// Paketin baytları — `AgentSessionTransferring.importArchive`'a gider.
    func download(sessionID: String) async throws -> Data
    func upload(_ upload: SharedSessionUpload) async throws -> SharedSession
    func delete(sessionID: String) async throws
}

public protocol SessionSharingMaking: Sendable {
    func makeClient(baseURL: URL, token: String) -> any SessionSharing
}

/// Sunucu token'ının deposu (Keychain). Token config'e asla yazılmaz.
public protocol SessionServerCredentialStoring: Sendable {
    func token(for serverID: String) async -> KeychainReadResult
    func setToken(_ token: String, for serverID: String) async throws
    func deleteToken(for serverID: String) async throws
}
