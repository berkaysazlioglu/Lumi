import Foundation

/// Orchestrator'ın Lumi'ye uzanan eli (karar 114 Faz 2): Lumi'nin loopback MCP
/// sunucusu. Claude `--mcp-config` ile bu uca bağlanır; araç çağrıları
/// `OrchestratorToolHandling`'e düşer.
public struct OrchestratorControlEndpoint: Sendable, Equatable {
    public let port: UInt16
    /// `Authorization: Bearer <token>` — aynı kullanıcı hesabındaki başka
    /// süreçlerin araçları çağırmasını engeller.
    public let token: String

    public init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    public var url: String { "http://127.0.0.1:\(port)/mcp" }
}

/// Bir araç çağrısının sonucu — MCP `content: [{type: text}]` + `isError`.
public struct OrchestratorToolResult: Sendable, Equatable {
    public let text: String
    public let isError: Bool

    public init(text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    public static func failure(_ text: String) -> OrchestratorToolResult {
        OrchestratorToolResult(text: text, isError: true)
    }
}

/// Araçların yürütücüsü. `arguments` ham JSON nesnesidir (MCP
/// `params.arguments`); doğrulama yürütücünün işidir.
public protocol OrchestratorToolHandling: Sendable {
    func call(name: String, arguments: Data) async -> OrchestratorToolResult
}

public protocol OrchestratorControlServing: Sendable {
    /// Sunucuyu başlatır (idempotent — çalışıyorsa aynı uç döner).
    func start(handler: any OrchestratorToolHandling) async throws -> OrchestratorControlEndpoint
    func stop() async
}
