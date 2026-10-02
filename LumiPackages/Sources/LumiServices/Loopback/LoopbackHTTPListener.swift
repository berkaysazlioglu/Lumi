import Foundation
import LumiKit
import Network

/// `127.0.0.1:<rastgele port>` üzerinde dinleyen asgari HTTP sunucusu — hook
/// sunucusu (karar 45) ve orchestrator'ın MCP sunucusu (karar 103) ortak
/// kullanır. Her bağlantı tek isteklik: istek `HTTPRequestParser` ile çözülür,
/// handler'a verilir, handler'ın `reply`'ı yanıtı yazıp bağlantıyı kapatır.
///
/// Handler dinleyici kuyruğunda çağrılır; `reply` istenen an (eşzamanlı ya da
/// bir `Task` içinden sonra) çağrılabilir. Bozuk istek 400 ile handler'a
/// uğramadan kapanır.
final class LoopbackHTTPListener: @unchecked Sendable {
    typealias Reply = @Sendable (Data) -> Void
    typealias Handler = @Sendable (HTTPRequest, @escaping Reply) -> Void

    /// Bağlantı başına okuma parçası.
    static let receiveChunk = 64 * 1024

    private let queue: DispatchQueue
    private let domain: String
    private let lock = NSLock()
    private var listener: NWListener?
    /// Canlı bağlantılar — NWConnection referans tutulmazsa erken serbest kalır.
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(label: String, domain: String) {
        queue = DispatchQueue(label: label, qos: .utility)
        self.domain = domain
    }

    /// Dinlemeye başlar ve portu döner.
    func start(handler: @escaping Handler) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw LumiError.underlying(domain: domain, message: error.localizedDescription)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, handler: handler)
        }

        let domain = self.domain
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let raw = listener.port?.rawValue else {
                        resumed.run { continuation.resume(throwing: LumiError.underlying(
                            domain: domain, message: "listener has no port"
                        )) }
                        return
                    }
                    resumed.run { continuation.resume(returning: raw) }
                case .failed(let error):
                    resumed.run { continuation.resume(throwing: LumiError.underlying(
                        domain: domain, message: error.localizedDescription
                    )) }
                case .cancelled:
                    resumed.run { continuation.resume(throwing: LumiError.underlying(
                        domain: domain, message: "listener cancelled"
                    )) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        lock.withLock { self.listener = listener }
        return port
    }

    func stop() {
        let (listener, connections) = lock.withLock {
            defer {
                self.listener = nil
                self.connections.removeAll()
            }
            return (self.listener, Array(self.connections.values))
        }
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        connections.forEach { $0.cancel() }
    }

    // MARK: - Bağlantı

    private func accept(_ connection: NWConnection, handler: @escaping Handler) {
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
        receive(on: connection, buffer: Data(), handler: handler)
    }

    private func forget(_ key: ObjectIdentifier) {
        lock.withLock { _ = connections.removeValue(forKey: key) }
    }

    private func receive(on connection: NWConnection, buffer: Data, handler: @escaping Handler) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunk) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequestParser.parse(buffer) {
            case .complete(let request):
                handler(request) { response in Self.finish(connection, with: response) }
            case .malformed:
                Self.finish(connection, with: HTTPRequestParser.response(status: 400, reason: "Bad Request"))
            case .incomplete:
                if error != nil || isComplete {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer, handler: handler)
                }
            }
        }
    }

    private static func finish(_ connection: NWConnection, with response: Data) {
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
