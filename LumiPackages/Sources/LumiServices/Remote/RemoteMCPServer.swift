import Foundation
import LumiKit
import OSLog

/// Claude terminallerinin Mac'ten Mac'e remote araçları için loopback MCP sunucusu
/// (karar 143, Faz 5). Orchestrator'ınkiyle aynı yönlendirici (`MCPRequestRouter`),
/// ayrı araç listesi (`RemoteMCPTools`) ve kendi token'ı. Token terminallerin
/// ortamına girer (`RemoteMCPEndpoint.environment`) — aynı kullanıcının başka
/// süreçleri onu bilmeden araç çağıramaz.
public final class RemoteMCPServer: RemoteMCPServing, @unchecked Sendable {
    private let listener = LoopbackHTTPListener(label: "lumi.remote.mcp", domain: "RemoteMCPServer")
    private let lock = NSLock()
    private var endpoint: RemoteMCPEndpoint?
    private let tokenGenerator: @Sendable () -> String
    private static let log = LumiLog.logger("remote")

    public init(tokenGenerator: @escaping @Sendable () -> String = AgentHookServer.randomToken) {
        self.tokenGenerator = tokenGenerator
    }

    public func start(handler: any OrchestratorToolHandling) async throws -> RemoteMCPEndpoint {
        if let existing = lock.withLock({ endpoint }) { return existing }
        let token = tokenGenerator()
        let port = try await listener.start { request, reply in
            let disposition = MCPRequestRouter.route(
                request, isAuthorized: { $0 == "Bearer \(token)" }, tools: RemoteMCPTools.specs, serverVersion: "1")
            switch disposition {
            case .reply(let status, let body):
                reply(HTTPRequestParser.response(status: status, reason: LumiMCPServer.reason(status), body: body))
            case .callTool(let id, let name, let arguments):
                Self.log.info("remote tool call → \(name, privacy: .public)")
                Task {
                    let result = await handler.call(name: name, arguments: arguments)
                    reply(HTTPRequestParser.response(
                        status: 200, reason: "OK", body: MCPRequestRouter.toolResponse(id: id, result: result)))
                }
            }
        }
        let resolved = RemoteMCPEndpoint(port: port, token: token)
        lock.withLock { endpoint = resolved }
        return resolved
    }

    public func stop() async {
        lock.withLock { endpoint = nil }
        listener.stop()
    }
}
