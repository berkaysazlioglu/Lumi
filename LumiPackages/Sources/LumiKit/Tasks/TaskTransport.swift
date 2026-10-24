import Foundation

/// Ham HTTP yanıtı — adapter durum kodunu ve gövdeyi kendisi yorumlar.
public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public let headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// HTTP dikişi (Tasks planı, Faz 2): canlıda URLSession, testlerde scriptli
/// fake. Ağ hatası fırlatır; HTTP hata durumları FIRLATMAZ, yanıt olarak döner.
public protocol HTTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// Kaynak token'larının deposu (Keychain). Token config'e asla yazılmaz.
public protocol TaskCredentialStoring: Sendable {
    func token(for source: TaskSourceID) async -> KeychainReadResult
    func setToken(_ token: String, for source: TaskSourceID) async throws
    func deleteToken(for source: TaskSourceID) async throws
}

public extension TaskProviding {
    /// Görsel indirirken eklenecek `Authorization` başlığı. Yalnız kaynağın
    /// kendi sunucusundaki adresler için dolu döner; başka hostlara token gitmez.
    func authorization(for url: URL) -> String? { nil }
}
