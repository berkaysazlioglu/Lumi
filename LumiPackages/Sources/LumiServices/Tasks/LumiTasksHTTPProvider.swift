import Foundation
import LumiKit

/// Custom adapter: kullanıcının sunucusundaki Lumi Tasks Protocol v1
/// (`TaskSetupPrompt`).
///
/// Her başarısız istek `TaskRequestFailure` olarak fırlar — istek satırı,
/// HTTP durumu, sunucunun hata zarfı ve yanıtın başıyla — ki hata kaydı
/// sunucuyu düzeltmeye yetecek ayrıntıyı göstersin. Token yalnız
/// `Authorization` başlığında gider; hiçbir hata metnine girmez.
public struct LumiTasksHTTPProvider: TaskProviding {
    /// Heroku'nun uyuyan dyno'su ilk istekte ~10 sn uyanır.
    static let timeout: TimeInterval = 20
    static let pageLimit = 200
    /// Sayfalama sonsuz döngüye girmesin (sunucu hep aynı imleci dönerse).
    static let maxPages = 50

    private let baseURL: URL
    private let token: String?
    private let transport: any HTTPTransporting

    public init(baseURL: URL, token: String?, transport: any HTTPTransporting) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    // MARK: - TaskProviding

    public func discover() async throws -> TaskSourceInfo {
        let response = try await perform("GET", "", operation: .discover)
        do {
            return try LumiTasksWire.discovery(response.json)
        } catch {
            throw failure(
                .invalidResponse("discovery"), operation: .discover, request: requestLine("GET", ""),
                response: response.raw, message: Self.describe(error as? LumiTasksWire.DiscoveryProblem)
            )
        }
    }

    public func listTasks() async throws -> [TaskItem] {
        var tasks: [TaskItem] = []
        var cursor: String?
        var seenCursors = Set<String>()
        for _ in 0..<Self.maxPages {
            var query = [URLQueryItem(name: "limit", value: String(Self.pageLimit))]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let response = try await perform("GET", "/tasks", query: query, operation: .listTasks)
            guard let object = response.json as? [String: Any], let items = object["tasks"] as? [Any] else {
                throw failure(
                    .invalidResponse("list"), operation: .listTasks, request: requestLine("GET", "/tasks"),
                    response: response.raw, message: #"Expected { "tasks": [...], "nextCursor": … }"#
                )
            }
            tasks += items.compactMap(LumiTasksWire.task)
            guard let next = LumiTasksWire.string(object["nextCursor"]), !next.isEmpty,
                  seenCursors.insert(next).inserted else { break }
            cursor = next
        }
        return tasks
    }

    public func update(taskID: String, patch: TaskPatch) async throws -> TaskItem {
        let path = "/tasks/" + Self.escape(taskID)
        let response = try await perform("PATCH", path, body: LumiTasksWire.body(for: patch), operation: .update, taskID: taskID)
        return try decodeTask(response, operation: .update, request: requestLine("PATCH", path), taskID: taskID)
    }

    public func create(_ draft: TaskDraft) async throws -> TaskItem {
        let response = try await perform("POST", "/tasks", body: LumiTasksWire.body(for: draft), operation: .create)
        return try decodeTask(response, operation: .create, request: requestLine("POST", "/tasks"), taskID: nil)
    }

    public func delete(taskID: String) async throws {
        _ = try await perform("DELETE", "/tasks/" + Self.escape(taskID), operation: .delete, taskID: taskID)
    }

    public func listUsers() async throws -> [TaskUser] {
        let response = try await perform("GET", "/users", operation: .listUsers)
        guard let users = (response.json as? [String: Any])?["users"] as? [Any] else {
            throw failure(
                .invalidResponse("users"), operation: .listUsers, request: requestLine("GET", "/users"),
                response: response.raw, message: #"Expected { "users": [...] }"#
            )
        }
        return users.compactMap(LumiTasksWire.user)
    }

    public func listProjects() async throws -> [TaskProjectRef] {
        let response = try await perform("GET", "/projects", operation: .listProjects)
        guard let projects = (response.json as? [String: Any])?["projects"] as? [Any] else {
            throw failure(
                .invalidResponse("projects"), operation: .listProjects, request: requestLine("GET", "/projects"),
                response: response.raw, message: #"Expected { "projects": [...] }"#
            )
        }
        return projects.compactMap(LumiTasksWire.project)
    }

    /// Yalnız kaynağın kendi origin'indeki görsellere token gider.
    public func authorization(for url: URL) -> String? {
        guard let token, url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port else { return nil }
        return "Bearer \(token)"
    }

    // MARK: - İstek

    private struct Response {
        let raw: HTTPResponse
        let json: Any?
    }

    private func perform(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        operation: TaskOperation,
        taskID: String? = nil
    ) async throws -> Response {
        let line = requestLine(method, path)
        var components = URLComponents(url: endpoint(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else {
            throw TaskRequestFailure(kind: .invalidResponse("bad address"), operation: operation, request: line, taskID: taskID)
        }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let response: HTTPResponse
        do {
            response = try await transport.send(request)
        } catch {
            // İptal ağ hatası değildir — çağıran kendi iptalini tanısın.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw TaskRequestFailure(
                kind: .unreachable(Self.networkMessage(error)), operation: operation, request: line, taskID: taskID
            )
        }
        let json = response.body.isEmpty ? nil : try? JSONSerialization.jsonObject(with: response.body)
        guard (200..<300).contains(response.status) else {
            throw errorFailure(response, json: json, operation: operation, request: line, taskID: taskID)
        }
        if !response.body.isEmpty, json == nil {
            throw failure(
                .invalidResponse("not JSON"), operation: operation, request: line, response: response,
                message: "The response body is not JSON", taskID: taskID
            )
        }
        return Response(raw: response, json: json)
    }

    private func decodeTask(_ response: Response, operation: TaskOperation, request: String, taskID: String?) throws -> TaskItem {
        guard let task = LumiTasksWire.task(response.json) else {
            throw failure(
                .invalidResponse("task"), operation: operation, request: request, response: response.raw,
                message: "Expected a task object with at least \"id\"", taskID: taskID
            )
        }
        return task
    }

    /// HTTP hata durumu → tür + sunucunun kendi zarfı.
    private func errorFailure(
        _ response: HTTPResponse, json: Any?, operation: TaskOperation, request: String, taskID: String?
    ) -> TaskRequestFailure {
        let envelope = LumiTasksWire.envelope(json)
        let kind: TaskProviderError = switch response.status {
        case 401, 403: .unauthorized
        case 404: .notFound
        case 409: .conflict
        case 405, 501: .unsupported(operation.title.lowercased())
        default: .invalidResponse("HTTP \(response.status)")
        }
        var message = envelope.message
        if message == nil {
            message = "HTTP \(response.status) without the { \"error\": { \"code\", \"message\" } } envelope"
        }
        if response.status == 429, let retry = response.header("Retry-After") {
            message = (message ?? "") + " (retry after \(retry)s)"
        }
        return TaskRequestFailure(
            kind: kind, operation: operation, request: request, httpStatus: response.status,
            serverCode: envelope.code, serverMessage: message,
            responseExcerpt: Self.excerpt(response.body), taskID: taskID
        )
    }

    private func failure(
        _ kind: TaskProviderError, operation: TaskOperation, request: String, response: HTTPResponse,
        message: String, taskID: String? = nil
    ) -> TaskRequestFailure {
        TaskRequestFailure(
            kind: kind, operation: operation, request: request, httpStatus: response.status,
            serverMessage: message, responseExcerpt: Self.excerpt(response.body), taskID: taskID
        )
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: baseURL.absoluteString + "/lumi/v1" + path) ?? baseURL
    }

    private func requestLine(_ method: String, _ path: String) -> String {
        "\(method) /lumi/v1\(path)"
    }

    private static func escape(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    private static func excerpt(_ body: Data) -> String? {
        guard !body.isEmpty else { return nil }
        return String(decoding: body.prefix(TaskRequestFailure.excerptLimit * 2), as: UTF8.self)
    }

    private static func networkMessage(_ error: any Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .timedOut: return "The request timed out after \(Int(timeout))s (a sleeping server can take a while to wake up)."
        case .cannotFindHost, .dnsLookupFailed: return "The host can't be found — check the address."
        case .cannotConnectToHost: return "Nothing is listening at this address — is the server running?"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            return "The HTTPS connection failed (certificate problem)."
        case .notConnectedToInternet: return "This Mac is offline."
        default: return urlError.localizedDescription
        }
    }

    private static func describe(_ problem: LumiTasksWire.DiscoveryProblem?) -> String {
        switch problem {
        case .notAnObject: #"GET /lumi/v1 must return a JSON object"#
        case .wrongProtocol(let name):
            #"GET /lumi/v1 must return "protocol": "lumi-tasks""# + (name.map { #" (got ""# + $0 + #"")"# } ?? "")
        case .missingVersion: #"GET /lumi/v1 must return "version": 1"#
        case nil: "Unexpected discovery response"
        }
    }
}
