import Foundation
import LumiKit
import OSLog

/// Orchestrator'ın kontrol yüzeyi (karar 104 Faz 2): loopback MCP sunucusu.
/// Claude `--mcp-config` ile `http://127.0.0.1:<port>/mcp`'ye bağlanır;
/// `tools/call` istekleri `OrchestratorToolHandling`'e gider ve yanıt araç
/// bitince yazılır. Sunucu orchestrator ilk başladığında tembel açılır.
public final class LumiMCPServer: OrchestratorControlServing, @unchecked Sendable {
    private let listener = LoopbackHTTPListener(label: "lumi.orchestrator.mcp", domain: "LumiMCPServer")
    private let lock = NSLock()
    private var endpoint: OrchestratorControlEndpoint?
    private let tokenGenerator: @Sendable () -> String
    private let serverVersion: String
    private static let log = LumiLog.logger("orchestrator")

    public init(
        serverVersion: String = "1",
        tokenGenerator: @escaping @Sendable () -> String = AgentHookServer.randomToken
    ) {
        self.serverVersion = serverVersion
        self.tokenGenerator = tokenGenerator
    }

    public func start(handler: any OrchestratorToolHandling) async throws -> OrchestratorControlEndpoint {
        if let existing = lock.withLock({ endpoint }) { return existing }
        let token = tokenGenerator()
        let version = serverVersion
        let port = try await listener.start { request, reply in
            switch MCPRequestRouter.route(request, token: token, serverVersion: version) {
            case .reply(let status, let body):
                reply(HTTPRequestParser.response(status: status, reason: Self.reason(status), body: body))
            case .callTool(let id, let name, let arguments):
                Self.log.info("tool call → \(name, privacy: .public)")
                Task {
                    let result = await handler.call(name: name, arguments: arguments)
                    let body = MCPRequestRouter.toolResponse(id: id, result: result)
                    reply(HTTPRequestParser.response(status: 200, reason: "OK", body: body))
                }
            }
        }
        let resolved = OrchestratorControlEndpoint(port: port, token: token)
        lock.withLock { endpoint = resolved }
        return resolved
    }

    public func stop() async {
        lock.withLock { endpoint = nil }
        listener.stop()
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Error"
        }
    }
}
