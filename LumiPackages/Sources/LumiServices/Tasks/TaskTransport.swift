import Foundation
import LumiKit

/// URLSession'lı HTTP taşıması. Ağ hatası (`URLError`) fırlatır; HTTP hata
/// durumlarını yanıt olarak döner — yorum adapter'ındır.
public struct URLSessionTransport: HTTPTransporting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return HTTPResponse(status: 0, body: data)
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http.statusCode, body: data, headers: headers)
    }
}

/// Task kaynağı token'ları Keychain'de: servis `com.lumi.tasks`, hesap kaynak kimliği.
public struct KeychainTaskCredentialStore: TaskCredentialStoring {
    public static let service = "com.lumi.tasks"

    private let keychain: any KeychainAccessing

    public init(keychain: any KeychainAccessing = SecurityKeychain()) {
        self.keychain = keychain
    }

    public func token(for source: TaskSourceID) async -> KeychainReadResult {
        await keychain.password(service: Self.service, account: source.rawValue)
    }

    public func setToken(_ token: String, for source: TaskSourceID) async throws {
        try await keychain.setPassword(token, service: Self.service, account: source.rawValue)
    }

    public func deleteToken(for source: TaskSourceID) async throws {
        try await keychain.deletePassword(service: Self.service, account: source.rawValue)
    }
}
