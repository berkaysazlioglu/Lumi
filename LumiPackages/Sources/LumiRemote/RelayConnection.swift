import Foundation
import LumiKit

public enum RelayInbound: @unchecked Sendable {
    case stateChanged(RemoteConnectionState)
    case message(type: String, payload: [String: Any])
    /// Relay soketi kapattı; `code` WebSocket kapanış kodudur (relay'in 4000–4005'i,
    /// docs/design/08). Ardından yeniden bağlanma denenir — çağıran `stop()` ile keser.
    case closed(code: Int, reason: String?)
}

public protocol RelayConnecting: Actor {
    func start(url: URL, hello: [String: Any])
    func stop()
    func send(type: String, payload: [String: Any])
    func inbound() -> AsyncStream<RelayInbound>
}

/// URLSessionWebSocketTask tabanlı relay istemcisi. Kopunca üstel geri
/// çekilmeyle aynı hello'yla yeniden bağlanır (spec §4.2, §9).
actor RelayConnection: RelayConnecting {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var backoff = ReconnectBackoff()
    private var continuation: AsyncStream<RelayInbound>.Continuation?
    private var currentURL: URL?
    private var currentHello: [String: Any] = [:]
    private var stopped = true

    init(session: URLSession = .shared) {
        self.session = session
    }

    func inbound() -> AsyncStream<RelayInbound> {
        let (stream, continuation) = AsyncStream.makeStream(of: RelayInbound.self)
        self.continuation = continuation
        return stream
    }

    func start(url: URL, hello: [String: Any]) {
        stopped = false
        currentURL = url
        currentHello = hello
        connect()
    }

    func stop() {
        stopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        continuation?.yield(.stateChanged(.disconnected))
    }

    func send(type: String, payload: [String: Any]) {
        guard let task, let data = RemoteProtocol.envelope(type: type, payload: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in } // hata → receive döngüsü zaten kopmayı görür
    }

    private func connect() {
        receiveTask?.cancel()
        guard !stopped, let url = currentURL else { return }
        continuation?.yield(.stateChanged(.connecting))
        let wsTask = session.webSocketTask(with: url)
        task = wsTask
        wsTask.resume()
        if let data = RemoteProtocol.envelope(type: "hello", payload: currentHello),
           let text = String(data: data, encoding: .utf8) {
            wsTask.send(.string(text)) { _ in }
        }
        receiveTask = Task { [weak self] in
            await self?.receiveLoop(on: wsTask)
        }
    }

    private func receiveLoop(on wsTask: URLSessionWebSocketTask) async {
        var receivedAny = false
        while !Task.isCancelled {
            do {
                let message = try await wsTask.receive()
                if !receivedAny {
                    receivedAny = true
                    backoff.reset()
                    continuation?.yield(.stateChanged(.connected))
                }
                let text: String
                switch message {
                case .string(let s): text = s
                case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
                @unknown default: text = ""
                }
                if let decoded = RemoteProtocol.decode(text: text) {
                    continuation?.yield(.message(type: decoded.type, payload: decoded.payload))
                }
            } catch {
                break
            }
        }
        guard !stopped, wsTask === task else { return }
        if wsTask.closeCode != .invalid {
            let reason = wsTask.closeReason.flatMap { String(data: $0, encoding: .utf8) }
            continuation?.yield(.closed(code: wsTask.closeCode.rawValue, reason: reason))
        }
        continuation?.yield(.stateChanged(.disconnected))
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        let delay = backoff.nextDelay()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.connect()
        }
    }
}
