import Foundation
import LumiKit

/// Kullanıcının sunucusundaki Lumi Sessions Protocol v1 (karar 138,
/// `SessionShareSetupPrompt`).
///
/// Her başarısız istek `SessionShareFailure` olarak fırlar — istek satırı,
/// HTTP durumu, sunucunun hata zarfı ve yanıtın başıyla. Token yalnız
/// `Authorization` başlığında gider; hiçbir hata metnine girmez. Değer
/// okuma hoşgörüsü (sayı kimlik, kesirli tarih, `{ "error": "msg" }`) Tasks
/// adapter'ının `LumiTasksWire`'ından gelir.
public struct LumiSessionsHTTPClient: SessionSharing {
    static let prefix = "/lumi/sessions/v1"
    /// Heroku'nun uyuyan dyno'su ilk istekte ~10 sn uyanır.
    static let timeout: TimeInterval = 20
    /// 64 MB'a kadar paket yükleme/indirme.
    static let transferTimeout: TimeInterval = 180
    static let pageLimit = 200
    static let maxPages = 50

    private let baseURL: URL
    private let token: String
    private let transport: any HTTPTransporting

    public init(baseURL: URL, token: String, transport: any HTTPTransporting) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    // MARK: - SessionSharing

    public func discover() async throws -> SessionServerInfo {
        let response = try await perform("GET", "")
        guard let object = response.json as? [String: Any] else {
            throw invalid(response, "GET", "", "GET \(Self.prefix) must return a JSON object")
        }
        guard object["protocol"] as? String == "lumi-sessions", LumiTasksWire.int(object["version"]) == 1 else {
            throw SessionShareFailure(
                kind: .unsupportedVersion, request: line("GET", ""), httpStatus: response.raw.status,
                responseExcerpt: Self.excerpt(response.raw.body)
            )
        }
        guard let me = Self.uploader(object["me"]) else {
            throw invalid(response, "GET", "", #"Discovery must include "me": { "id", "name" }"#)
        }
        let name = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return SessionServerInfo(name: name, me: me, maxUploadBytes: LumiTasksWire.int(object["maxUploadBytes"]))
    }

    public func listSessions() async throws -> [SharedSession] {
        var sessions: [SharedSession] = []
        var cursor: String?
        var seenCursors = Set<String>()
        for _ in 0..<Self.maxPages {
            var query = [URLQueryItem(name: "limit", value: String(Self.pageLimit))]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let response = try await perform("GET", "/sessions", query: query)
            guard let items = (response.json as? [String: Any])?["sessions"] as? [Any] else {
                throw invalid(response, "GET", "/sessions", #"Expected { "sessions": [...], "nextCursor": … }"#)
            }
            sessions += items.compactMap(Self.session)
            guard let next = LumiTasksWire.string((response.json as? [String: Any])?["nextCursor"]), !next.isEmpty,
                  seenCursors.insert(next).inserted else { break }
            cursor = next
        }
        return sessions.sorted { $0.uploadedAt > $1.uploadedAt }
    }

    public func download(sessionID: String) async throws -> Data {
        let path = "/sessions/" + Self.escape(sessionID)
        let response = try await perform("GET", path, timeout: Self.transferTimeout)
        guard let archive = (response.json as? [String: Any])?["archive"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: archive) else {
            throw invalid(response, "GET", path, #"Expected the session with an "archive" object"#)
        }
        return data
    }

    public func upload(_ upload: SharedSessionUpload) async throws -> SharedSession {
        let response = try await perform(
            "POST", "/sessions", body: try Self.uploadBody(upload), timeout: Self.transferTimeout
        )
        guard let session = Self.session(response.json) else {
            throw invalid(response, "POST", "/sessions", "Expected the created session summary")
        }
        return session
    }

    public func delete(sessionID: String) async throws {
        _ = try await perform("DELETE", "/sessions/" + Self.escape(sessionID))
    }

    // MARK: - Wire

    /// Paket zaten JSON baytı: 64 MB'ı yeniden ayrıştırmamak için gövde
    /// küçük alanlar + ham `archive` olarak elle birleştirilir.
    static func uploadBody(_ upload: SharedSessionUpload) throws -> Data {
        guard upload.archive.first == UInt8(ascii: "{") else {
            throw SessionShareFailure(kind: .invalidResponse("the session package is not a JSON object"))
        }
        let fields: [String: Any] = [
            "title": upload.title, "project": upload.project, "provider": upload.provider.rawValue,
        ]
        var body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        body.removeLast() // `}`
        body.append(Data(#","archive":"#.utf8))
        body.append(upload.archive)
        body.append(UInt8(ascii: "}"))
        return body
    }

    static func session(_ value: Any?) -> SharedSession? {
        guard let object = value as? [String: Any],
              let id = LumiTasksWire.string(object["id"]), !id.isEmpty,
              let uploader = uploader(object["uploader"]),
              let uploadedAt = LumiTasksWire.date(object["uploadedAt"]) else { return nil }
        let title = (object["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled session"
        return SharedSession(
            id: id, title: title, project: object["project"] as? String ?? "",
            provider: (object["provider"] as? String).flatMap(AgentProvider.init(rawValue:)),
            uploader: uploader, uploadedAt: uploadedAt, sizeBytes: LumiTasksWire.int(object["size"])
        )
    }

    static func uploader(_ value: Any?) -> SharedSessionUploader? {
        guard let object = value as? [String: Any], let id = LumiTasksWire.string(object["id"]), !id.isEmpty
        else { return nil }
        let name = (object["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id
        return SharedSessionUploader(id: id, name: name)
    }

    // MARK: - İstek

    private struct Response {
        let raw: HTTPResponse
        let json: Any?
    }

    private func perform(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
        timeout: TimeInterval = Self.timeout
    ) async throws -> Response {
        var components = URLComponents(string: baseURL.absoluteString + Self.prefix + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else {
            throw SessionShareFailure(kind: .invalidResponse("bad address"), request: line(method, path))
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw SessionShareFailure(
                kind: .unreachable(HTTPNetworkMessage.describe(error, timeout: timeout)), request: line(method, path)
            )
        }
        let json = response.body.isEmpty ? nil : try? JSONSerialization.jsonObject(with: response.body)
        guard (200..<300).contains(response.status) else {
            throw errorFailure(response, json: json, request: line(method, path))
        }
        if !response.body.isEmpty, json == nil {
            throw invalid(Response(raw: response, json: nil), method, path, "The response body is not JSON")
        }
        return Response(raw: response, json: json)
    }

    private func errorFailure(_ response: HTTPResponse, json: Any?, request: String) -> SessionShareFailure {
        let envelope = LumiTasksWire.envelope(json)
        let kind: SessionShareFailure.Kind = switch response.status {
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .notFound
        case 413: .tooLarge
        case 503 where envelope.code == "not_configured": .notConfigured
        default: .invalidResponse("HTTP \(response.status)")
        }
        return SessionShareFailure(
            kind: kind, request: request, httpStatus: response.status, serverCode: envelope.code,
            serverMessage: envelope.message
                ?? #"HTTP \#(response.status) without the { "error": { "code", "message" } } envelope"#,
            responseExcerpt: Self.excerpt(response.body)
        )
    }

    private func invalid(_ response: Response, _ method: String, _ path: String, _ message: String) -> SessionShareFailure {
        SessionShareFailure(
            kind: .invalidResponse(message), request: line(method, path), httpStatus: response.raw.status,
            serverMessage: message, responseExcerpt: Self.excerpt(response.raw.body)
        )
    }

    private func line(_ method: String, _ path: String) -> String {
        "\(method) \(Self.prefix)\(path)"
    }

    private static func escape(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    private static func excerpt(_ body: Data) -> String? {
        guard !body.isEmpty else { return nil }
        return String(decoding: body.prefix(SessionShareFailure.excerptLimit * 2), as: UTF8.self)
    }
}

/// Canlı istemci fabrikası.
public struct LiveSessionSharingFactory: SessionSharingMaking {
    private let transport: any HTTPTransporting

    public init(transport: any HTTPTransporting = URLSessionTransport()) {
        self.transport = transport
    }

    public func makeClient(baseURL: URL, token: String) -> any SessionSharing {
        LumiSessionsHTTPClient(baseURL: baseURL, token: token, transport: transport)
    }
}

/// Oturum sunucusu token'ı Keychain'de: servis `com.lumi.sessions`, hesap sunucu kimliği.
public struct KeychainSessionServerCredentialStore: SessionServerCredentialStoring {
    public static let service = "com.lumi.sessions"

    private let keychain: any KeychainAccessing

    public init(keychain: any KeychainAccessing = SecurityKeychain()) {
        self.keychain = keychain
    }

    public func token(for serverID: String) async -> KeychainReadResult {
        await keychain.password(service: Self.service, account: serverID)
    }

    public func setToken(_ token: String, for serverID: String) async throws {
        try await keychain.setPassword(token, service: Self.service, account: serverID)
    }

    public func deleteToken(for serverID: String) async throws {
        try await keychain.deletePassword(service: Self.service, account: serverID)
    }
}
