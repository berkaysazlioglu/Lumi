import Foundation
import LumiKit

public enum RelayInbound: @unchecked Sendable {
    case stateChanged(RemoteConnectionState)
    case message(type: String, payload: [String: Any])
    /// Relay soketi kapattı; `code` WebSocket kapanış kodudur (relay'in 4000–4005'i,
    /// docs/design/08). Ardından yeniden bağlanma denenir — çağıran `stop()` ile keser.
    case closed(code: Int, reason: String?)
    /// Sunucu bağlantıyı kalıcı olarak reddetti (401 / 4007, karar 146). Yeniden
    /// bağlanma DENENMEZ; çağıran yeni adres/token'la `start` edene kadar kanal kapalı kalır.
    case rejected(RemoteServerIssue)
    /// Sunucu bu ağdan gelen bağlantıyı reddetti (4006 allowlist, karar 147). Ret ağa
    /// bağlıdır: yeniden bağlanma sürer, ağ değişince beklemeden denenir. Sonraki
    /// `.stateChanged(.connected)` engelin kalktığını söyler.
    case blocked(RemoteServerIssue)
}

public protocol RelayConnecting: Actor {
    func start(endpoint: RelayEndpoint, hello: [String: Any])
    func stop()
    func send(type: String, payload: [String: Any])
    func inbound() -> AsyncStream<RelayInbound>
}

/// URLSessionWebSocketTask tabanlı relay istemcisi. El sıkışmada server token'ını
/// `Authorization: Bearer` olarak gönderir (karar 146). Kopunca üstel geri çekilmeyle
/// aynı hello'yla yeniden bağlanır (spec §4.2, §9); ağ yeniden kullanılabilir olunca
/// beklemeyi keser (karar 147). Sunucu kalıcı olarak reddederse
/// (`RemoteServerIssue.isPermanent`) durur.
actor RelayConnection: RelayConnecting {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var backoff: ReconnectBackoff
    private let network: any NetworkPathSignaling
    private var networkTask: Task<Void, Never>?
    private var continuation: AsyncStream<RelayInbound>.Continuation?
    private var currentEndpoint: RelayEndpoint?
    private var currentHello: [String: Any] = [:]
    private var stopped = true

    init(
        session: URLSession = .shared,
        network: any NetworkPathSignaling = NetworkPathSignal.shared,
        backoff: ReconnectBackoff = ReconnectBackoff()
    ) {
        self.session = session
        self.network = network
        self.backoff = backoff
    }

    func inbound() -> AsyncStream<RelayInbound> {
        let (stream, continuation) = AsyncStream.makeStream(of: RelayInbound.self)
        self.continuation = continuation
        return stream
    }

    func start(endpoint: RelayEndpoint, hello: [String: Any]) {
        stopped = false
        currentEndpoint = endpoint
        currentHello = hello
        watchNetworkIfNeeded()
        connect()
    }

    func stop() {
        stopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        networkTask?.cancel()
        networkTask = nil
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
        reconnectTask = nil
        receiveTask?.cancel()
        guard !stopped, let endpoint = currentEndpoint else { return }
        continuation?.yield(.stateChanged(.connecting))
        var request = URLRequest(url: endpoint.url)
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        let wsTask = session.webSocketTask(with: request)
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
        let status = (wsTask.response as? HTTPURLResponse)?.statusCode
        let code = wsTask.closeCode == .invalid ? nil : wsTask.closeCode.rawValue
        if let code {
            let reason = wsTask.closeReason.flatMap { String(data: $0, encoding: .utf8) }
            continuation?.yield(.closed(code: code, reason: reason))
        }
        continuation?.yield(.stateChanged(.disconnected))
        if let issue = Self.serverIssue(httpStatus: receivedAny ? nil : status, closeCode: code) {
            guard !issue.isPermanent else {
                stopped = true
                networkTask?.cancel()
                networkTask = nil
                continuation?.yield(.rejected(issue))
                return
            }
            continuation?.yield(.blocked(issue))
        }
        scheduleReconnect()
    }

    /// Sunucunun retleri: el sıkışmada 401 ve sunucunun 4006/4007'si. Hangisinin
    /// yeniden denenmeyeceğini `RemoteServerIssue.isPermanent` söyler.
    static func serverIssue(httpStatus: Int?, closeCode: Int?) -> RemoteServerIssue? {
        if httpStatus == 401 { return .unauthorized }
        switch closeCode {
        case 4006: return .networkNotAllowed
        case 4007: return .tokenRevoked
        default: return nil
        }
    }

    /// Ağ yeniden kullanılabilir olunca geri çekilme beklemesini kes (karar 147).
    private func watchNetworkIfNeeded() {
        guard networkTask == nil else { return }
        let changes = network.changes()
        networkTask = Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                await self.retryNowIfWaiting()
            }
        }
    }

    /// Yalnız geri çekilme beklemesindeyken etkilidir — kurulu ya da kurulmakta olan
    /// bağlantıya dokunmaz.
    func retryNowIfWaiting() {
        guard !stopped, let pending = reconnectTask else { return }
        pending.cancel()
        backoff.reset()
        connect()
    }

    private func scheduleReconnect() {
        let delay = backoff.nextDelay()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            await self?.reconnectUnlessCancelled()
        }
    }

    /// İptal denetimi actor içinde yapılır: `retryNowIfWaiting` bu görevi iptal edip
    /// kendisi bağlandıysa ikinci bir `connect` koşmaz.
    private func reconnectUnlessCancelled() {
        guard !Task.isCancelled else { return }
        connect()
    }
}
