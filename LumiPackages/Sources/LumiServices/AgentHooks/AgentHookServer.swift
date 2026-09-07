import Foundation
import LumiKit
import Network

/// Loopback hook sunucusu (karar 45): `127.0.0.1:<rastgele port>` üzerinde
/// dinler, kurulu hook script'lerinin `curl` POST'larını kabul eder, token +
/// terminal başlığını doğrular ve `AgentHookEvent` yayar.
///
/// Neden HTTP: Claude Code / Codex hook'ları düz shell komutu çalıştırır ve
/// `curl` her macOS'ta hazırdır; Unix soketi ya da özel istemci binary'si
/// kurulum yükü getirirdi (Orca ile aynı tercih). Her bağlantı tek isteklik:
/// yanıt yazılır, bağlantı kapanır.
public final class AgentHookServer: AgentHookServing, @unchecked Sendable {
    private let queue = DispatchQueue(label: "lumi.agent-hooks.server", qos: .utility)
    private let lock = NSLock()
    private var listener: NWListener?
    private var endpoint: AgentHookEndpoint?
    /// Canlı bağlantılar — NWConnection referans tutulmazsa erken serbest kalır.
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let broadcaster = EventBroadcaster<AgentHookEvent>()
    private let tokenGenerator: @Sendable () -> String

    /// Bağlantı başına okuma parçası.
    static let receiveChunk = 64 * 1024

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

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw LumiError.underlying(domain: "AgentHookServer", message: error.localizedDescription)
        }
        let token = tokenGenerator()
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, token: token)
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let raw = listener.port?.rawValue else {
                        resumed.run { continuation.resume(throwing: LumiError.underlying(
                            domain: "AgentHookServer", message: "listener has no port"
                        )) }
                        return
                    }
                    resumed.run { continuation.resume(returning: raw) }
                case .failed(let error):
                    resumed.run { continuation.resume(throwing: LumiError.underlying(
                        domain: "AgentHookServer", message: error.localizedDescription
                    )) }
                case .cancelled:
                    resumed.run { continuation.resume(throwing: LumiError.underlying(
                        domain: "AgentHookServer", message: "listener cancelled"
                    )) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        let resolved = AgentHookEndpoint(port: port, token: token)
        lock.withLock {
            self.listener = listener
            self.endpoint = resolved
        }
        return resolved
    }

    public func stop() async {
        let (listener, connections) = lock.withLock {
            defer {
                self.listener = nil
                self.endpoint = nil
                self.connections.removeAll()
            }
            return (self.listener, Array(self.connections.values))
        }
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        connections.forEach { $0.cancel() }
    }

    public func events() -> AsyncStream<AgentHookEvent> {
        broadcaster.stream()
    }

    /// Şu an dinlenen uç nokta (testler ve tanılama).
    public var currentEndpoint: AgentHookEndpoint? { lock.withLock { endpoint } }

    // MARK: - Bağlantı

    private func accept(_ connection: NWConnection, token: String) {
        let key = ObjectIdentifier(connection)
        lock.withLock { connections[key] = connection }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.forget(key)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data(), token: token)
    }

    private func forget(_ key: ObjectIdentifier) {
        lock.withLock { _ = connections.removeValue(forKey: key) }
    }

    private func receive(on connection: NWConnection, buffer: Data, token: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunk) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequestParser.parse(buffer) {
            case .complete(let request):
                self.respond(to: request, on: connection, token: token)
            case .malformed:
                self.finish(connection, with: HTTPRequestParser.response(status: 400, reason: "Bad Request"))
            case .incomplete:
                if error != nil || isComplete {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer, token: token)
                }
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection, token: String) {
        switch AgentHookRequestRouter.route(request, token: token) {
        case .accepted(let event):
            broadcaster.send(event)
            finish(connection, with: HTTPRequestParser.response(status: 200, reason: "OK"))
        case .rejected(let status, let reason):
            finish(connection, with: HTTPRequestParser.response(status: status, reason: reason))
        }
    }

    private func finish(_ connection: NWConnection, with response: Data) {
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// `withCheckedThrowingContinuation` yalnız bir kez sürdürülebilir; NWListener
/// durum akışı ise birden çok kez çağırır (`ready` sonrası `cancelled`).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
