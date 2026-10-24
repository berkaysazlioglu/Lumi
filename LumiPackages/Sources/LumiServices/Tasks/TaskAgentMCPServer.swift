import Foundation
import LumiKit
import OSLog

/// Task ajanlarının loopback MCP sunucusu (karar 137, Faz 3).
///
/// Orchestrator'ınkinden ayrıdır: araçları başka (`TaskAgentTools`), ve token
/// tek değil **terminal başına**dır — her `register` o task'e kapsamlı bir
/// token ve `--mcp-config` dosyası üretir, araç çağrısı token'dan kaydına
/// çözülür. Bir ajan başka bir task'i teslim edemez. Sunucu ilk kayıtta
/// tembel açılır; dosyalar `0600` yazılır ve kayıt düşünce silinir.
public final class TaskAgentMCPServer: TaskAgentToolServing, @unchecked Sendable {
    private struct Registration {
        let details: String
        let onSubmit: @Sendable (String) async -> String
    }

    private let listener = LoopbackHTTPListener(label: "lumi.tasks.mcp", domain: "TaskAgentMCPServer")
    private let lock = NSLock()
    private var port: UInt16?
    private var registrations: [String: Registration] = [:]
    private let directory: URL
    private let tokenGenerator: @Sendable () -> String
    private static let log = LumiLog.logger("tasks")

    public init(directory: URL, tokenGenerator: @escaping @Sendable () -> String = AgentHookServer.randomToken) {
        self.directory = directory
        self.tokenGenerator = tokenGenerator
    }

    public func register(
        details: String,
        onSubmit: @escaping @Sendable (String) async -> String
    ) async throws -> TaskAgentToolSession {
        let port = try await ensureStarted()
        let token = tokenGenerator()
        lock.withLock { registrations[token] = Registration(details: details, onSubmit: onSubmit) }
        let file = directory.appendingPathComponent("\(UUID().uuidString).json")
        do {
            try Self.writeConfig(to: file, port: port, token: token)
        } catch {
            lock.withLock { registrations[token] = nil }
            throw error
        }
        return TaskAgentToolSession(configPath: file.path, token: token)
    }

    public func unregister(_ session: TaskAgentToolSession) async {
        lock.withLock { registrations[session.token] = nil }
        try? FileManager.default.removeItem(atPath: session.configPath)
    }

    // MARK: - Sunucu

    private func ensureStarted() async throws -> UInt16 {
        if let port = lock.withLock({ port }) { return port }
        let started = try await listener.start { [weak self] request, reply in
            self?.handle(request, reply: reply)
        }
        lock.withLock { port = started }
        return started
    }

    private func handle(_ request: HTTPRequest, reply: @escaping LoopbackHTTPListener.Reply) {
        let token = Self.bearer(request.header("Authorization"))
        let registration = token.flatMap { token in lock.withLock { registrations[token] } }
        let disposition = MCPRequestRouter.route(
            request, isAuthorized: { _ in registration != nil }, tools: TaskAgentTools.specs, serverVersion: "1"
        )
        switch disposition {
        case .reply(let status, let body):
            reply(HTTPRequestParser.response(status: status, reason: LumiMCPServer.reason(status), body: body))
        case .callTool(let id, let name, let arguments):
            guard let registration else { return }
            Self.log.info("task tool call → \(name, privacy: .public)")
            Task {
                let result = await Self.call(name, arguments: arguments, registration: registration)
                reply(HTTPRequestParser.response(status: 200, reason: "OK", body: MCPRequestRouter.toolResponse(id: id, result: result)))
            }
        }
    }

    private static func call(_ name: String, arguments: Data, registration: Registration) async -> OrchestratorToolResult {
        switch name {
        case TaskAgentTools.getTask:
            return OrchestratorToolResult(text: registration.details)
        case TaskAgentTools.submitForReview:
            let object = (try? JSONSerialization.jsonObject(with: arguments)) as? [String: Any]
            guard let summary = (object?["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !summary.isEmpty else {
                return .failure("summary is required: say what you changed and how you verified it.")
            }
            return OrchestratorToolResult(text: await registration.onSubmit(summary))
        default:
            return .failure("Unknown tool \(name).")
        }
    }

    static func bearer(_ header: String?) -> String? {
        guard let header, header.hasPrefix("Bearer ") else { return nil }
        return String(header.dropFirst("Bearer ".count))
    }

    /// Claude Code'un `--mcp-config` biçimi; token içerdiği için yalnız sahibi okur.
    static func writeConfig(to file: URL, port: UInt16, token: String) throws {
        let config: [String: Any] = [
            "mcpServers": [
                OrchestratorTools.serverName: [
                    "type": "http",
                    "url": "http://127.0.0.1:\(port)/mcp",
                    "headers": ["Authorization": "Bearer \(token)"],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
