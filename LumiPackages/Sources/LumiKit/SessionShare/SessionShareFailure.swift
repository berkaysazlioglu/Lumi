import Foundation

/// Oturum sunucusuna giden başarısız bir isteğin kaydı (karar 138).
///
/// Tasks'in `TaskRequestFailure`'ı gibi amaç sunucuyu yazan kişinin (ya da
/// ajanın) hatayı tek bakışta düzeltmesidir: istek satırı, HTTP durumu,
/// sunucunun hata zarfı ve yanıtın başı. Token ASLA girmez.
public struct SessionShareFailure: Error, LocalizedError, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case unauthorized
        case forbidden
        case notFound
        case tooLarge
        case notConfigured
        case unsupportedVersion
        case unreachable(String)
        case invalidResponse(String)
    }

    public let kind: Kind
    /// `GET /lumi/sessions/v1/sessions` gibi.
    public let request: String?
    public let httpStatus: Int?
    public let serverCode: String?
    public let serverMessage: String?
    public let responseExcerpt: String?

    public static let excerptLimit = 600

    public init(
        kind: Kind, request: String? = nil, httpStatus: Int? = nil,
        serverCode: String? = nil, serverMessage: String? = nil, responseExcerpt: String? = nil
    ) {
        self.kind = kind
        self.request = request
        self.httpStatus = httpStatus
        self.serverCode = serverCode
        self.serverMessage = serverMessage
        self.responseExcerpt = responseExcerpt.map { String($0.prefix(Self.excerptLimit)) }
    }

    /// Kısa, tek satırlık özet — toast ve bağlanma ekranı.
    public var summary: String {
        var parts: [String] = []
        if let httpStatus { parts.append("HTTP \(httpStatus)") }
        if let serverCode { parts.append(serverCode) }
        let message = serverMessage ?? defaultMessage
        return parts.isEmpty ? message : parts.joined(separator: " · ") + " — " + message
    }

    public var errorDescription: String? { summary }

    private var defaultMessage: String {
        switch kind {
        case .unauthorized: "The server rejected the token."
        case .forbidden: "Only the uploader can delete this session."
        case .notFound: "The session no longer exists on the server."
        case .tooLarge: "The session is larger than the server accepts."
        case .notConfigured: "The server has no Lumi Sessions users yet."
        case .unsupportedVersion: "The server doesn't speak Lumi Sessions Protocol v1."
        case .unreachable(let detail): detail
        case .invalidResponse(let detail): "Unexpected response: \(detail)."
        }
    }

    /// Protokolün bu durumda ne beklediği.
    public var hint: String {
        switch kind {
        case .unauthorized:
            "Every request needs Authorization: Bearer <token> with a token created by the server's add-user command."
        case .forbidden:
            "DELETE must answer 403 forbidden only when the token's user didn't upload the session."
        case .notFound:
            "Check that \(request ?? "the route") matches the Lumi Sessions Protocol path under /lumi/sessions/v1."
        case .tooLarge:
            "Raise the JSON body limit for POST /lumi/sessions/v1/sessions to at least 64 MB, or answer 413 payload_too_large."
        case .notConfigured:
            "Run the server's add-user command to create a user and its token."
        case .unsupportedVersion:
            #"GET /lumi/sessions/v1 must return "protocol": "lumi-sessions" and "version": 1."#
        case .unreachable:
            "Lumi couldn't reach the server. Check the address, that the app is running, and HTTPS."
        case .invalidResponse:
            #"Errors must use { "error": { "code", "message" } } and successful responses the documented JSON shape."#
        }
    }

    /// Ajana yapıştırılacak ayrıntılı rapor.
    public var agentReport: String {
        var lines = ["A Lumi Sessions request failed — please fix the server:", ""]
        if let request { lines.append("- Request: \(request)") }
        if let httpStatus { lines.append("- HTTP status: \(httpStatus)") }
        if let serverCode { lines.append("- Server error code: \(serverCode)") }
        lines.append("- Message: \(serverMessage ?? defaultMessage)")
        lines.append("- Expected: \(hint)")
        if let responseExcerpt, !responseExcerpt.isEmpty {
            lines += ["", "Response body (first \(Self.excerptLimit) characters):", "```", responseExcerpt, "```"]
        }
        return lines.joined(separator: "\n")
    }
}
