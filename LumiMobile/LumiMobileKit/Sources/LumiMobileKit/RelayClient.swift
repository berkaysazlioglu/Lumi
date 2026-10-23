import Foundation
import LumiWire

public enum ConnectionState: Sendable, Equatable {
    case disconnected, connecting, connected
}

public enum ClientEvent: Sendable, Equatable {
    case stateChanged(ConnectionState)
    case message(ServerMessage)
}

/// 1, 2, 4, 8, … 60 s exponential back-off (mirrors the Mac-side ReconnectBackoff).
public struct ReconnectBackoff: Sendable {
    private var attempt = 0
    private let capSeconds: Double = 60

    public init() {}

    public mutating func nextDelay() -> Double {
        let delay = min(pow(2, Double(attempt)), capSeconds)
        attempt += 1
        return delay
    }

    public mutating func reset() { attempt = 0 }
}

/// The boundary AppModel sees — tests implement this via FakeRelayClient.
public protocol RelayClienting: Sendable {
    func events() async -> AsyncStream<ClientEvent>
    func start(pairing: PairingInfo) async
    func stop() async
    @discardableResult func send(command: OutgoingCommand) async -> Bool
    /// Sends a raw envelope frame (terminal-mirror subscribe/unsubscribe/input).
    @discardableResult func send(frame: String) async -> Bool
    func registerPush(deviceToken: String) async
    func unregisterPush(deviceToken: String) async
    /// App came to the foreground (decision 130): verify a "connected" socket with a
    /// ping and reconnect at once if it is dead; skip a pending back-off wait.
    func reconnectIfStale() async
}

public extension RelayClienting {
    func reconnectIfStale() async {}
}

/// Client that connects to the relay as the phone role: hello → welcome → message stream;
/// reconnects with exponential back-off on disconnect (design §9).
public actor RelayClient: RelayClienting {
    public private(set) var state: ConnectionState = .disconnected

    private let connect: ConnectionFactory
    private let sleep: @Sendable (Double) async -> Void
    private var backoff = ReconnectBackoff()
    private var connection: (any WebSocketConnection)?
    private var runTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<ClientEvent>.Continuation] = [:]
    /// Back-off wait between reconnect attempts; cancelled to reconnect immediately.
    private var backoffWait: Task<Void, Never>?
    /// Incremented on every pong — `reconnectIfStale` waits for it to move.
    private var pongCount = 0
    /// Bumped per socket so a stale check never closes a newer connection.
    private var connectionEpoch = 0
    private let pongTimeout: Duration

    public init(
        connect: @escaping ConnectionFactory = { URLSessionWebSocketConnection(url: $0) },
        sleep: @escaping @Sendable (Double) async -> Void = { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        },
        pongTimeout: Duration = .seconds(2)
    ) {
        self.connect = connect
        self.sleep = sleep
        self.pongTimeout = pongTimeout
    }

    public func events() -> AsyncStream<ClientEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func start(pairing: PairingInfo) {
        guard runTask == nil, let url = URL(string: pairing.relayUrl) else { return }
        let token = pairing.token
        runTask = Task { await run(url: url, token: token) }
    }

    public func stop() {
        runTask?.cancel()
        runTask = nil
        connection?.close()
        connection = nil
        backoff.reset()
        setState(.disconnected)
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    @discardableResult
    public func send(command: OutgoingCommand) async -> Bool {
        await sendFrame(PhoneProtocol.commandFrame(command))
    }

    @discardableResult
    public func send(frame: String) async -> Bool {
        await sendFrame(frame)
    }

    public func registerPush(deviceToken: String) async {
        _ = await sendFrame(PhoneProtocol.registerPushFrame(deviceToken: deviceToken))
    }

    public func unregisterPush(deviceToken: String) async {
        _ = await sendFrame(PhoneProtocol.unregisterPushFrame(deviceToken: deviceToken))
    }

    public func reconnectIfStale() async {
        guard runTask != nil else { return }
        guard state == .connected, let connection else {
            // Already reconnecting: drop the remaining back-off and try now.
            backoff.reset()
            backoffWait?.cancel()
            return
        }
        let before = pongCount
        let epoch = connectionEpoch
        guard await sendFrame(PhoneProtocol.pingFrame()) else {
            connection.close()
            return
        }
        let step = Duration.milliseconds(100)
        var waited = Duration.zero
        while waited < pongTimeout {
            try? await Task.sleep(for: step)
            waited += step
            if pongCount != before { return }
        }
        // Still the same socket and no pong → it died in the background.
        guard epoch == connectionEpoch else { return }
        DiagLog.shared.log("relay", "foreground ping timed out → reconnect")
        backoff.reset()
        connection.close()
    }

    // MARK: Internal

    private func run(url: URL, token: String) async {
        while !Task.isCancelled {
            setState(.connecting)
            DiagLog.shared.log("relay", "connecting \(url.host ?? url.absoluteString)")
            let conn = connect(url)
            connection = conn
            connectionEpoch &+= 1
            do {
                try await conn.send(PhoneProtocol.helloFrame(token: token))
                for try await frame in conn.incoming {
                    guard let message = PhoneProtocol.decodeServerMessage(frame) else {
                        DiagLog.shared.log("relay", "decode edilemeyen frame \(frame.prefix(80))")
                        continue
                    }
                    if case .welcome = message {
                        backoff.reset()
                        setState(.connected)
                    }
                    if case .pong = message { pongCount &+= 1 }
                    yield(.message(message))
                }
                DiagLog.shared.log("relay", "stream closed (server side)")
            } catch {
                // disconnected → retry below with back-off
                DiagLog.shared.log("relay", "dropped: \(error.localizedDescription)")
            }
            connection = nil
            if Task.isCancelled { return }
            setState(.disconnected)
            let delay = backoff.nextDelay()
            let wait = Task { [sleep] in await sleep(delay) }
            backoffWait = wait
            await wait.value
            backoffWait = nil
        }
    }

    private func sendFrame(_ frame: String) async -> Bool {
        guard let connection else {
            DiagLog.shared.log("relay", "send skipped (no connection)")
            return false
        }
        do {
            try await connection.send(frame)
            return true
        } catch {
            DiagLog.shared.log("relay", "send failed: \(error.localizedDescription)")
            return false
        }
    }

    private func setState(_ newState: ConnectionState) {
        guard state != newState else { return }
        state = newState
        DiagLog.shared.log("relay", "state \(newState)")
        yield(.stateChanged(newState))
    }

    private func yield(_ event: ClientEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
