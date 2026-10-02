import Foundation
import LumiKit

/// Loopback hook sunucusu (karar 45): `127.0.0.1:<rastgele port>` üzerinde
/// dinler, kurulu hook script'lerinin `curl` POST'larını kabul eder, token +
/// terminal başlığını doğrular ve `AgentHookEvent` yayar.
///
/// Neden HTTP: Claude Code / Codex hook'ları düz shell komutu çalıştırır ve
/// `curl` her macOS'ta hazırdır; Unix soketi ya da özel istemci binary'si
/// kurulum yükü getirirdi (Orca ile aynı tercih). Her bağlantı tek isteklik:
/// yanıt yazılır, bağlantı kapanır.
public final class AgentHookServer: AgentHookServing, @unchecked Sendable {
    private let listener = LoopbackHTTPListener(label: "lumi.agent-hooks.server", domain: "AgentHookServer")
    private let lock = NSLock()
    private var endpoint: AgentHookEndpoint?
    private let broadcaster = EventBroadcaster<AgentHookEvent>(label: "agentHooks")
    private let tokenGenerator: @Sendable () -> String

    public init(tokenGenerator: @escaping @Sendable () -> String = AgentHookServer.randomToken) {
        self.tokenGenerator = tokenGenerator
    }

    /// 192-bit rastgele sır, hex. `SystemRandomNumberGenerator` Apple
    /// platformlarında kriptografik olarak güvenlidir.
    public static func randomToken() -> String {
        (0 ..< 24).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    public func start() async throws -> AgentHookEndpoint {
        if let existing = lock.withLock({ endpoint }) { return existing }
        let token = tokenGenerator()
        let port = try await listener.start { [weak self] request, reply in
            guard let self else { return reply(HTTPRequestParser.response(status: 503, reason: "Unavailable")) }
            reply(self.respond(to: request, token: token))
        }
        let resolved = AgentHookEndpoint(port: port, token: token)
        lock.withLock { self.endpoint = resolved }
        return resolved
    }

    public func stop() async {
        lock.withLock { endpoint = nil }
        listener.stop()
    }

    public func events() -> AsyncStream<AgentHookEvent> {
        broadcaster.stream()
    }

    /// Şu an dinlenen uç nokta (testler ve tanılama).
    public var currentEndpoint: AgentHookEndpoint? { lock.withLock { endpoint } }

    // MARK: - İstek

    /// Olay yanıttan ÖNCE yayınlanır: hook script'i yanıtı bekler, bir
    /// sonraki hook'u ancak ondan sonra yollar — sıra korunur.
    private func respond(to request: HTTPRequest, token: String) -> Data {
        switch AgentHookRequestRouter.route(request, token: token) {
        case .accepted(let event):
            DiagLog.shared.log("hook", "recv accepted: kind=\(event.kind) tool=\(event.toolName ?? "-") path=\(request.path)")
            broadcaster.send(event)
            return HTTPRequestParser.response(status: 200, reason: "OK")
        case .rejected(let status, let reason):
            DiagLog.shared.log("hook", "recv rejected: \(status) \(reason) path=\(request.path)")
            return HTTPRequestParser.response(status: status, reason: reason)
        }
    }
}
