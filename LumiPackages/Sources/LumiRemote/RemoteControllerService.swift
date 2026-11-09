import Foundation
import LumiKit

/// Mac'ten Mac'e remote'un controller tarafı (docs/design/08-mac-remote.md, Faz 3).
///
/// Sunucuya (karar 146: adres + server token'ı) bir **directory** soketi açar (`hubs` listesi) ve
/// bağlanılan her hub için ayrı bir `RemoteHubLink` tutar. Hub çevrimdışı olup
/// geri gelince bellekteki şifreyle kendiliğinden yeniden bağlanır; şifre
/// reddedilirse (4003) yeniden denemez. Hatırlanan şifreler Keychain'de
/// `com.lumi.remote-controller` / `<hubId>` altında durur.
@MainActor
public final class RemoteControllerService: RemoteControllerServicing {
    public static let keychainService = "com.lumi.remote-controller"

    public private(set) var directoryState: RemoteConnectionState = .disconnected
    public private(set) var hubs: [RemoteHubInfo] = []
    /// Directory soketinin kalıcı reddi (karar 146); yeniden yapılandırılınca temizlenir.
    public private(set) var directoryIssue: RemoteServerIssue?

    private struct Settings: Equatable {
        let endpoint: RelayEndpoint
        let identity: RemoteControllerIdentity
    }

    private let makeConnection: @MainActor () -> any RelayConnecting
    private let keychain: any KeychainAccessing
    private let broadcaster = EventBroadcaster<RemoteControllerEvent>()
    private var settings: Settings?
    private var directory: (any RelayConnecting)?
    private var directoryTask: Task<Void, Never>?
    private var links: [String: RemoteHubLink] = [:]

    public init(
        keychain: any KeychainAccessing,
        makeConnection: (@MainActor () -> any RelayConnecting)? = nil
    ) {
        self.keychain = keychain
        self.makeConnection = makeConnection ?? { RelayConnection() }
    }

    public func events() -> AsyncStream<RemoteControllerEvent> { broadcaster.stream() }

    public func linkState(_ hubId: String) -> RemoteHubLinkState {
        links[hubId]?.state ?? .disconnected
    }

    public func snapshot(_ hubId: String) -> RemoteHubSnapshot? {
        links[hubId]?.snapshot
    }

    // MARK: - Directory

    public func configure(endpoint: RelayEndpoint?, identity: RemoteControllerIdentity) {
        let next = endpoint.map { Settings(endpoint: $0, identity: identity) }
        guard next != settings else { return }
        let serverChanged = next?.endpoint != settings?.endpoint
        settings = next
        Task { await self.reopenDirectory(dropLinks: serverChanged) }
    }

    public func stop() {
        settings = nil
        Task { await self.reopenDirectory(dropLinks: true) }
    }

    private func reopenDirectory(dropLinks: Bool) async {
        directoryTask?.cancel()
        directoryTask = nil
        if let directory { await directory.stop() }
        directory = nil
        if dropLinks {
            let all = links.values
            links.removeAll()
            for link in all { await link.shutdown() }
        }
        setHubs([])
        setDirectoryIssue(nil)
        guard let settings else {
            setDirectoryState(.disconnected)
            return
        }
        let connection = makeConnection()
        directory = connection
        let stream = await connection.inbound()
        directoryTask = Task { [weak self] in
            for await inbound in stream { self?.handleDirectory(inbound) }
        }
        setDirectoryState(.connecting)
        await connection.start(endpoint: settings.endpoint, hello: [
            "role": "controller",
            "controllerId": settings.identity.controllerId, "name": settings.identity.name,
        ])
    }

    private func handleDirectory(_ inbound: RelayInbound) {
        switch inbound {
        case .stateChanged(let state):
            setDirectoryState(state)
        case .message("hubs", let payload):
            guard let settings else { return }
            setHubs(RemoteControllerWire.hubs(payload, excluding: settings.identity.ownHubId))
            reconnectReturningHubs()
        case .rejected(let issue):
            setDirectoryIssue(issue)
        case .message, .closed:
            break
        }
    }

    /// Bekleyen bağlantılardan hub'ı yeniden çevrimiçi olanları açar.
    private func reconnectReturningHubs() {
        for hub in hubs where hub.isOnline {
            guard let link = links[hub.id], link.state == .waitingForHub, let password = link.password else { continue }
            Task { await self.open(link, password: password) }
        }
    }

    // MARK: - Hub bağlantıları

    public func connect(hubId: String, password: String?, remember: Bool) async {
        let resolved: String?
        if let password {
            resolved = password
        } else {
            resolved = await keychain.password(service: Self.keychainService, account: hubId).value
        }
        guard let resolved else {
            notify(hubId: hubId, state: .rejected(reason: "password_required"))
            return
        }
        if password != nil {
            if remember {
                try? await keychain.setPassword(resolved, service: Self.keychainService, account: hubId)
            } else {
                try? await keychain.deletePassword(service: Self.keychainService, account: hubId)
            }
        }
        let link = links[hubId] ?? makeLink(hubId)
        await open(link, password: resolved)
    }

    public func disconnect(hubId: String) {
        guard let link = links.removeValue(forKey: hubId) else { return }
        Task {
            await link.shutdown()
            self.notify(hubId: hubId, state: .disconnected)
        }
    }

    public func hasRememberedPassword(hubId: String) async -> Bool {
        await keychain.password(service: Self.keychainService, account: hubId).value != nil
    }

    public func terminalOutput(hubId: String, sessionId: String) -> AsyncStream<RemoteTerminalChunk> {
        guard let link = links[hubId] else { return AsyncStream { $0.finish() } }
        return link.terminalOutput(sessionId: sessionId)
    }

    public func sendInput(hubId: String, sessionId: String, data: Data) {
        links[hubId]?.sendInput(sessionId: sessionId, data: data)
    }

    public func chatEvents(hubId: String, sessionId: String, afterId: String?) -> AsyncStream<RemoteChatEvent> {
        guard let link = links[hubId] else { return AsyncStream { $0.finish() } }
        return link.chatEvents(sessionId: sessionId, afterId: afterId)
    }

    public func sendChat(hubId: String, sessionId: String, text: String) {
        links[hubId]?.sendChat(sessionId: sessionId, text: text)
    }

    public func respondPrompt(hubId: String, sessionId: String, itemId: String, revision: Int, answer: RemotePromptAnswer) {
        links[hubId]?.respondPrompt(sessionId: sessionId, itemId: itemId, revision: revision, answer: answer)
    }

    public func startSession(
        hubId: String, checkoutPath: String, kind: RemoteSessionKind, prompt: String
    ) async throws -> String? {
        guard let link = links[hubId] else { throw RemoteControllerError.notConnected }
        return try await link.command {
            RemoteControllerWire.startSessionCommand(commandId: $0, checkoutPath: checkoutPath, kind: kind, prompt: prompt)
        }.sessionId
    }

    public func sendText(hubId: String, sessionId: String, text: String, submit: Bool) async throws {
        guard let link = links[hubId] else { throw RemoteControllerError.notConnected }
        guard submit else {
            link.sendInput(sessionId: sessionId, data: Data(text.utf8))
            return
        }
        _ = try await link.command {
            RemoteControllerWire.sendTextCommand(commandId: $0, sessionId: sessionId, text: text)
        }
    }

    public func requestGrid(hubId: String, sessionId: String, grid: TerminalGrid) {
        links[hubId]?.sendInput(sessionId: sessionId, data: Data(), grid: grid)
    }

    public func pasteImage(hubId: String, sessionId: String, image: RemotePastedImage) async throws {
        guard let link = links[hubId], link.state.isConnected else { throw RemoteControllerError.notConnected }
        _ = try await link.command {
            RemoteControllerWire.pasteImageCommand(commandId: $0, sessionId: sessionId, image: image)
        }
    }

    /// Claude terminalinde transcript (yoksa ekran), diğerlerinde ekran.
    public func readTerminal(hubId: String, sessionId: String) async throws -> RemoteTerminalReading {
        guard let link = links[hubId], link.state.isConnected else { throw RemoteControllerError.notConnected }
        if link.snapshot.session(sessionId)?.provider == .claude,
           let messages = await link.readTranscript(sessionId: sessionId, timeout: Self.readTimeout),
           !messages.isEmpty {
            return .transcript(messages)
        }
        do {
            let reply = try await link.command {
                RemoteControllerWire.readScreenCommand(commandId: $0, sessionId: sessionId)
            }
            return .screen(reply.data["text"] ?? "")
        } catch RemoteControllerError.failed("unknown_action") {
            // `read_screen`'i bilmeyen eski hub: düz scrollback snapshot'ı.
        }
        guard let chunk = await link.readScreen(sessionId: sessionId, timeout: Self.readTimeout) else {
            throw RemoteControllerError.timedOut
        }
        return .screen(String(decoding: chunk.data, as: UTF8.self))
    }

    static let readTimeout: Duration = .seconds(8)

    public func closeSession(hubId: String, sessionId: String) async throws {
        guard let link = links[hubId] else { throw RemoteControllerError.notConnected }
        _ = try await link.command {
            RemoteControllerWire.deleteSessionCommand(commandId: $0, sessionId: sessionId)
        }
    }

    // MARK: - Yardımcılar

    private func makeLink(_ hubId: String) -> RemoteHubLink {
        let link = RemoteHubLink(hubId: hubId, connection: makeConnection()) { [weak self] link in
            self?.linkDidChange(link)
        }
        links[hubId] = link
        return link
    }

    private func open(_ link: RemoteHubLink, password: String) async {
        guard let settings else {
            notify(hubId: link.hubId, state: .rejected(reason: "no_server"))
            return
        }
        await link.open(endpoint: settings.endpoint, identity: settings.identity, password: password)
    }

    private func linkDidChange(_ link: RemoteHubLink) {
        if case .rejected(let reason) = link.state, reason == "wrong_password" {
            // Hatırlanan şifre artık geçersiz — bir dahaki sefere sorulsun.
            let hubId = link.hubId
            Task { try? await self.keychain.deletePassword(service: Self.keychainService, account: hubId) }
        }
        broadcaster.send(.linkChanged(hubId: link.hubId, link.state))
        broadcaster.send(.snapshotChanged(hubId: link.hubId, link.snapshot))
    }

    private func notify(hubId: String, state: RemoteHubLinkState) {
        broadcaster.send(.linkChanged(hubId: hubId, state))
    }

    private func setHubs(_ list: [RemoteHubInfo]) {
        guard hubs != list else { return }
        hubs = list
        broadcaster.send(.hubsChanged(list))
    }

    private func setDirectoryIssue(_ issue: RemoteServerIssue?) {
        guard directoryIssue != issue else { return }
        directoryIssue = issue
        broadcaster.send(.directoryIssueChanged(issue))
    }

    private func setDirectoryState(_ state: RemoteConnectionState) {
        guard directoryState != state else { return }
        directoryState = state
        broadcaster.send(.directoryStateChanged(state))
    }
}
