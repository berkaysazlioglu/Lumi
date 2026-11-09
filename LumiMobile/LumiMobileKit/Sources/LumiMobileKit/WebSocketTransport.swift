import Foundation

/// Abstraction for a single WebSocket connection. `incoming` ends when the connection
/// drops (with an error or normally); RelayClient treats this as the reconnect signal.
public protocol WebSocketConnection: Sendable {
    var incoming: AsyncThrowingStream<String, Error> { get }
    func send(_ text: String) async throws
    func close()
    /// After `incoming` ended: the handshake's HTTP status and the server's close code.
    /// RelayClient reads them to tell a permanent rejection (decision 146) from a drop.
    func endStatus() -> (httpStatus: Int?, closeCode: Int?)
}

public extension WebSocketConnection {
    func endStatus() -> (httpStatus: Int?, closeCode: Int?) { (nil, nil) }
}

/// Builds a connection for a handshake request (carries `Authorization: Bearer`).
public typealias ConnectionFactory = @Sendable (URLRequest) -> any WebSocketConnection

/// URLSessionWebSocketTask wrapper — thin I/O layer, no unit tests
/// (covered by Task 10 end-to-end verification).
/// @unchecked Sendable: task is assigned only in init; URLSessionWebSocketTask
/// provides a thread-safe API.
public final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    public let incoming: AsyncThrowingStream<String, Error>

    public init(request: URLRequest) {
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        self.incoming = AsyncThrowingStream { continuation in
            @Sendable func receiveNext() {
                task.receive { result in
                    switch result {
                    case .success(.string(let text)):
                        continuation.yield(text)
                        receiveNext()
                    case .success:
                        receiveNext() // binary frames are not expected; skip
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    }
                }
            }
            receiveNext()
            continuation.onTermination = { _ in
                task.cancel(with: .goingAway, reason: nil)
            }
        }
        task.resume()
    }

    public func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    public func close() {
        task.cancel(with: .goingAway, reason: nil)
    }

    public func endStatus() -> (httpStatus: Int?, closeCode: Int?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        return (status, task.closeCode == .invalid ? nil : task.closeCode.rawValue)
    }
}
