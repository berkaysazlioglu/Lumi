import Foundation
import LumiKit

/// Controller'ın tek bir hub'a bağlantısı (docs/design/08): kendi relay soketi,
/// hub'ın son anlık görüntüsü, açık terminal aynaları ve cevap bekleyen komutlar.
/// Durum değişikliklerini sahibine (`RemoteControllerService`) `onChange` ile bildirir.
@MainActor
final class RemoteHubLink {
    static let commandTimeout: Duration = .seconds(20)

    let hubId: String
    private(set) var state: RemoteHubLinkState = .disconnected
    private(set) var snapshot = RemoteHubSnapshot()
    /// Bu oturumda kullanılan şifre — hub geri gelince yeniden bağlanmak için bellekte tutulur.
    private(set) var password: String?

    private let connection: any RelayConnecting
    private let onChange: @MainActor (RemoteHubLink) -> Void
    private var inboundTask: Task<Void, Never>?
    /// Açık aynalar — oturum kimliği → (ayna kimliği, akış). Kimlik, eski aynanın geç gelen
    /// bitişinin aynı oturuma açılmış yeni aynayı kapatmasını önler.
    private var terminalSinks: [String: (token: UUID, continuation: AsyncStream<RemoteTerminalChunk>.Continuation)] = [:]
    /// Açık chat görünümleri (Claude terminalleri) — aynalarla aynı kimlik kuralı.
    private var chatSinks: [String: (token: UUID, continuation: AsyncStream<RemoteChatEvent>.Continuation)] = [:]
    /// Giden frame'ler tek tüketicili kuyruktan sırayla gider (tuş vuruşlarının sırası korunur).
    private let outbox: AsyncStream<OutboundFrame>.Continuation
    private var outboxTask: Task<Void, Never>?
    private var pendingCommands: [String: CheckedContinuation<RemoteControllerWire.CommandReply?, Never>] = [:]
    /// Tek seferlik okumalar: oturum → ilk `chat` / `scrollback` frame'ini bekleyen.
    private var transcriptWaiters: [String: CheckedContinuation<[ChatMessage]?, Never>] = [:]
    private var screenWaiters: [String: CheckedContinuation<RemoteTerminalChunk?, Never>] = [:]
    private var commandSeq = 0

    init(hubId: String, connection: any RelayConnecting, onChange: @escaping @MainActor (RemoteHubLink) -> Void) {
        self.hubId = hubId
        self.connection = connection
        self.onChange = onChange
        let (stream, continuation) = AsyncStream.makeStream(of: OutboundFrame.self)
        outbox = continuation
        outboxTask = Task {
            for await frame in stream {
                await connection.send(type: frame.type, payload: frame.payload)
            }
        }
    }

    deinit {
        outbox.finish()
    }

    // MARK: - Yaşam döngüsü

    func open(url: URL, network: String, identity: RemoteControllerIdentity, password: String) async {
        await close()
        self.password = password
        let stream = await connection.inbound()
        inboundTask = Task { [weak self] in
            for await inbound in stream { self?.handle(inbound) }
        }
        setState(.connecting)
        let hello: [String: Any] = [
            "role": "controller", "network": network,
            "controllerId": identity.controllerId, "name": identity.name,
            "attach": ["hubId": hubId, "password": password],
        ]
        nonisolated(unsafe) let frame = hello
        await connection.start(url: url, hello: frame)
    }

    /// Bağlantıyı kapatır. Açık aynalar bitmez — yeniden bağlanınca yeniden abone olunur.
    func close(forgetPassword: Bool = false) async {
        inboundTask?.cancel()
        inboundTask = nil
        await connection.stop()
        failPendingCommands()
        if forgetPassword { password = nil }
    }

    /// Kullanıcı bağlantıyı bitirdi: aynalar da kapanır.
    func shutdown() async {
        await close(forgetPassword: true)
        for sink in terminalSinks.values { sink.continuation.finish() }
        terminalSinks.removeAll()
        for sink in chatSinks.values { sink.continuation.finish() }
        chatSinks.removeAll()
        snapshot = RemoteHubSnapshot()
        setState(.disconnected)
    }

    // MARK: - Komutlar

    func terminalOutput(sessionId: String) -> AsyncStream<RemoteTerminalChunk> {
        let (stream, continuation) = AsyncStream.makeStream(of: RemoteTerminalChunk.self)
        let token = UUID()
        let previous = terminalSinks[sessionId]
        terminalSinks[sessionId] = (token, continuation)
        previous?.continuation.finish()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.releaseTerminal(sessionId, token: token) }
        }
        if state.isConnected { sendSubscribe(sessionId) }
        return stream
    }

    /// Chat akışı: `subscribe{mode:chat, afterId?}`; hub'da bu bağlantının chat modu
    /// aynadan ayrı izleyicidir. Akış bitince `unsubscribe{mode:chat}`.
    func chatEvents(sessionId: String, afterId: String?) -> AsyncStream<RemoteChatEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: RemoteChatEvent.self)
        let token = UUID()
        let previous = chatSinks[sessionId]
        chatSinks[sessionId] = (token, continuation)
        previous?.continuation.finish()
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.releaseChat(sessionId, token: token) }
        }
        if state.isConnected {
            send(type: "subscribe", payload: RemoteControllerWire.chatSubscribe(sessionId: sessionId, afterId: afterId))
        }
        return stream
    }

    func sendChat(sessionId: String, text: String) {
        guard state.isConnected else { return }
        send(type: "chat_send", payload: ["sessionId": sessionId, "text": text])
    }

    func respondPrompt(sessionId: String, itemId: String, revision: Int, answer: RemotePromptAnswer) {
        guard state.isConnected else { return }
        send(type: "prompt_respond", payload: RemoteControllerWire.promptRespond(
            sessionId: sessionId, itemId: itemId, revision: revision, answer: answer))
    }

    func sendInput(sessionId: String, data: Data, grid: TerminalGrid? = nil) {
        guard state.isConnected else { return }
        var payload: [String: Any] = ["sessionId": sessionId, "data": data.base64EncodedString()]
        if let grid {
            payload["cols"] = grid.cols
            payload["rows"] = grid.rows
        }
        send(type: "input", payload: payload)
    }

    /// Claude terminalinin transcript'ini bir kez okur (chat aboneliği; hub'da bu bağlantının
    /// chat modu ayrı izleyicidir, aynayı koparmaz). Zaman aşımında `nil`.
    func readTranscript(sessionId: String, timeout: Duration) async -> [ChatMessage]? {
        guard state.isConnected, transcriptWaiters[sessionId] == nil else { return nil }
        send(type: "subscribe", payload: ["sessionId": sessionId, "mode": "chat"])
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.transcriptWaiters.removeValue(forKey: sessionId)?.resume(returning: nil)
        }
        let messages = await withCheckedContinuation { transcriptWaiters[sessionId] = $0 }
        timer.cancel()
        // Açık chat görünümü aynı izleyici anahtarını kullanır; onu koparma.
        if chatSinks[sessionId] == nil {
            send(type: "unsubscribe", payload: ["sessionId": sessionId, "mode": "chat"])
        }
        return messages
    }

    /// Terminal ekranını (scrollback dahil düz metin) bir kez okur. Açık ayna varsa
    /// abonelik bırakılmaz.
    func readScreen(sessionId: String, timeout: Duration) async -> RemoteTerminalChunk? {
        guard state.isConnected, screenWaiters[sessionId] == nil else { return nil }
        sendSubscribe(sessionId)
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.screenWaiters.removeValue(forKey: sessionId)?.resume(returning: nil)
        }
        let chunk = await withCheckedContinuation { screenWaiters[sessionId] = $0 }
        timer.cancel()
        if terminalSinks[sessionId] == nil {
            send(type: "unsubscribe", payload: ["sessionId": sessionId, "mode": "terminal"])
        }
        return chunk
    }

    /// Komut gönderir ve `command_result`'ı bekler (en fazla `commandTimeout`).
    func command(_ build: (String) -> [String: Any]) async throws -> RemoteControllerWire.CommandReply {
        guard state.isConnected else { throw RemoteControllerError.notConnected }
        commandSeq += 1
        let commandId = "\(hubId.prefix(8))-\(commandSeq)"
        send(type: "command", payload: build(commandId))
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.commandTimeout)
            self?.resolveCommand(commandId, reply: nil)
        }
        let reply = await withCheckedContinuation { pendingCommands[commandId] = $0 }
        timeout.cancel()
        guard let reply else { throw state.isConnected ? RemoteControllerError.timedOut : .notConnected }
        guard reply.ok else { throw RemoteControllerError.failed(reply.error ?? "failed") }
        return reply
    }

    // MARK: - Gelen frame'ler

    private func handle(_ inbound: RelayInbound) {
        switch inbound {
        case .stateChanged(.disconnected):
            failPendingCommands()
            // Ağ koptu: RelayConnection kendiliğinden yeniden bağlanır (şifre hello'da).
            if state == .connected { setState(.connecting) }
        case .stateChanged:
            break
        case .closed(let code, let reason):
            handleClose(code: code, reason: reason)
        case .message(let type, let payload):
            handleMessage(type: type, payload: payload)
        }
    }

    private func handleClose(code: Int, reason: String?) {
        switch code {
        case 4003:
            // Şifre reddedildi ya da hub herkesi düşürdü (şifre değişti): yeniden denenmez.
            password = nil
            stopReconnecting()
            setState(.rejected(reason: reason ?? "unauthorized"))
        case 4000, 4004, 4005:
            // Hub düştü / yeniden bağlandı / cevap vermedi: directory hub'ı yeniden
            // çevrimiçi gösterince servis `password` ile yeniden açar.
            stopReconnecting()
            setState(.waitingForHub)
        default:
            break
        }
    }

    private func handleMessage(type: String, payload: [String: Any]) {
        switch type {
        case "welcome":
            snapshot.sessions = RemoteControllerWire.sessions(payload)
            let tree = RemoteControllerWire.tree(payload)
            snapshot.projects = tree.projects
            snapshot.others = tree.others
            setState(.connected)
            // Yeniden bağlanma: açık aynalar taze scrollback, chat'ler tam liste alsın.
            for sessionId in terminalSinks.keys { sendSubscribe(sessionId) }
            for sessionId in chatSinks.keys {
                send(type: "subscribe", payload: RemoteControllerWire.chatSubscribe(sessionId: sessionId, afterId: nil))
            }
        case "sessions":
            snapshot.sessions = RemoteControllerWire.sessions(payload)
            onChange(self)
        case "projects":
            let tree = RemoteControllerWire.tree(payload)
            snapshot.projects = tree.projects
            snapshot.others = tree.others
            onChange(self)
        case "scrollback", "data":
            guard let (sessionId, chunk) = RemoteControllerWire.terminalChunk(type: type, payload: payload) else { return }
            terminalSinks[sessionId]?.continuation.yield(chunk)
            if chunk.isSnapshot { screenWaiters.removeValue(forKey: sessionId)?.resume(returning: chunk) }
        case "chat", "chat_append", "chat_status", "prompt":
            guard let (sessionId, event) = RemoteControllerWire.chatEvent(type: type, payload: payload) else { return }
            chatSinks[sessionId]?.continuation.yield(event)
            if case .snapshot(let messages, _) = event {
                transcriptWaiters.removeValue(forKey: sessionId)?.resume(returning: messages)
            }
        case "command_result":
            guard let reply = RemoteControllerWire.commandReply(payload) else { return }
            resolveCommand(reply.commandId, reply: reply)
        default:
            break
        }
    }

    // MARK: - Yardımcılar

    private func sendSubscribe(_ sessionId: String) {
        send(type: "subscribe", payload: ["sessionId": sessionId, "mode": "terminal"])
    }

    private func releaseTerminal(_ sessionId: String, token: UUID) {
        // Aynı oturuma yeni bir ayna açıldıysa eskisinin bitişi onu kapatmamalı.
        guard terminalSinks[sessionId]?.token == token else { return }
        terminalSinks[sessionId] = nil
        if state.isConnected { send(type: "unsubscribe", payload: ["sessionId": sessionId, "mode": "terminal"]) }
    }

    private func releaseChat(_ sessionId: String, token: UUID) {
        guard chatSinks[sessionId]?.token == token else { return }
        chatSinks[sessionId] = nil
        // Süren tek seferlik okuma kendi unsubscribe'ını gönderecek.
        if state.isConnected, transcriptWaiters[sessionId] == nil {
            send(type: "unsubscribe", payload: ["sessionId": sessionId, "mode": "chat"])
        }
    }

    private func send(type: String, payload: [String: Any]) {
        outbox.yield(OutboundFrame(type: type, payload: payload))
    }

    private func resolveCommand(_ commandId: String, reply: RemoteControllerWire.CommandReply?) {
        pendingCommands.removeValue(forKey: commandId)?.resume(returning: reply)
    }

    private func failPendingCommands() {
        let pending = pendingCommands
        pendingCommands.removeAll()
        for continuation in pending.values { continuation.resume(returning: nil) }
        let transcripts = transcriptWaiters, screens = screenWaiters
        transcriptWaiters.removeAll()
        screenWaiters.removeAll()
        for continuation in transcripts.values { continuation.resume(returning: nil) }
        for continuation in screens.values { continuation.resume(returning: nil) }
    }

    private func stopReconnecting() {
        inboundTask?.cancel()
        inboundTask = nil
        failPendingCommands()
        Task { await connection.stop() }
    }

    private func setState(_ newState: RemoteHubLinkState) {
        guard state != newState else { onChange(self); return }
        state = newState
        onChange(self)
    }
}

/// Giden kuyruğun öğesi. `[String: Any]` Sendable değildir; frame kuyruğa girdikten
/// sonra hiç değiştirilmez ve tek tüketici tarafından bir kez gönderilir.
struct OutboundFrame: @unchecked Sendable {
    let type: String
    let payload: [String: Any]
}
