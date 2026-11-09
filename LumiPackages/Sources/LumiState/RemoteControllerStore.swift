import Foundation
import LumiKit

/// Uzak bir hub'daki terminalin adresi.
public struct RemoteSessionRef: Sendable, Equatable, Hashable {
    public let hubId: String
    public let sessionId: String

    public init(hubId: String, sessionId: String) {
        self.hubId = hubId
        self.sessionId = sessionId
    }
}

/// Uzak terminalin sağ taraftaki görünümü (karar 143 ek).
public enum RemoteSessionViewMode: Sendable, Hashable {
    /// Claude terminali için telefonla aynı chat hattı (boyuttan bağımsız).
    case chat
    /// Ham PTY aynası (TUI menüleri, trust ekranı, `/model` gibi durumlar için).
    case terminal
}

/// Mac'ten Mac'e remote'un controller tarafının UI köprüsü (docs/design/08):
/// hub listesi, bağlantı durumları, hub anlık görüntüleri ve Remote route'undaki seçim.
@Observable @MainActor
public final class RemoteControllerStore {
    public private(set) var directoryState: RemoteConnectionState
    public private(set) var hubs: [RemoteHubInfo]
    /// Sunucunun directory'yi kalıcı reddi (karar 146).
    public private(set) var directoryIssue: RemoteServerIssue?
    public private(set) var links: [String: RemoteHubLinkState] = [:]
    public private(set) var snapshots: [String: RemoteHubSnapshot] = [:]
    /// Ağaçta açık olan hub.
    public var selectedHubId: String?
    /// Sağ sütunda aynası gösterilen terminal.
    public var selectedSession: RemoteSessionRef?
    /// Kullanıcının terminal başına seçtiği görünüm; seçilmemişse Claude → chat.
    public private(set) var viewModes: [RemoteSessionRef: RemoteSessionViewMode] = [:]
    /// Son başarısız eylemin kullanıcıya gösterilecek açıklaması.
    public private(set) var lastError: String?

    private let service: any RemoteControllerServicing
    private var consumeTask: Task<Void, Never>?
    @ObservationIgnored private var chatSessions: [RemoteSessionRef: RemoteChatSession] = [:]

    public init(service: any RemoteControllerServicing) {
        self.service = service
        directoryState = service.directoryState
        hubs = service.hubs
    }

    public func start() {
        guard consumeTask == nil else { return }
        let stream = service.events()
        consumeTask = Task { [weak self] in
            for await event in stream { self?.apply(event) }
        }
    }

    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
        service.stop()
    }

    public func configure(endpoint: RelayEndpoint?, identity: RemoteControllerIdentity) {
        service.configure(endpoint: endpoint, identity: identity)
    }

    public func linkState(_ hubId: String) -> RemoteHubLinkState {
        links[hubId] ?? .disconnected
    }

    public func hub(_ hubId: String) -> RemoteHubInfo? {
        hubs.first { $0.id == hubId }
    }

    public var selectedSnapshot: RemoteHubSnapshot? {
        selectedHubId.flatMap { snapshots[$0] }
    }

    // MARK: - Eylemler

    /// `password` nil ise hatırlanan şifre denenir (yoksa durum `password_required` olur).
    public func connect(hubId: String, password: String?, remember: Bool) async {
        lastError = nil
        selectedHubId = hubId
        await service.connect(hubId: hubId, password: password, remember: remember)
    }

    public func disconnect(hubId: String) {
        if selectedSession?.hubId == hubId { selectedSession = nil }
        service.disconnect(hubId: hubId)
    }

    public func hasRememberedPassword(hubId: String) async -> Bool {
        await service.hasRememberedPassword(hubId: hubId)
    }

    public func select(_ ref: RemoteSessionRef) {
        selectedHubId = ref.hubId
        selectedSession = ref
    }

    /// Yeni terminal açar ve (kimliği dönerse) onu seçer.
    public func startSession(hubId: String, checkoutPath: String, kind: RemoteSessionKind) async {
        lastError = nil
        do {
            if let sessionId = try await service.startSession(hubId: hubId, checkoutPath: checkoutPath, kind: kind, prompt: "") {
                select(RemoteSessionRef(hubId: hubId, sessionId: sessionId))
            }
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// ⌘T Remote route'unda: seçili uzak terminalin checkout'unda yeni Claude terminali.
    /// Seçim yoksa ya da terminal bir checkout'ta değilse (serbest terminal) `false`.
    @discardableResult
    public func startSessionBesideSelection() -> Bool {
        guard let ref = selectedSession, linkState(ref.hubId).isConnected,
              let path = snapshots[ref.hubId]?.checkoutPath(of: ref.sessionId) else { return false }
        Task { await startSession(hubId: ref.hubId, checkoutPath: path, kind: .claude(model: nil)) }
        return true
    }

    public func closeSession(_ ref: RemoteSessionRef) async {
        lastError = nil
        do {
            try await service.closeSession(hubId: ref.hubId, sessionId: ref.sessionId)
            if selectedSession == ref { selectedSession = nil }
        } catch {
            lastError = Self.describe(error)
        }
    }

    public func terminalOutput(_ ref: RemoteSessionRef) -> AsyncStream<RemoteTerminalChunk> {
        service.terminalOutput(hubId: ref.hubId, sessionId: ref.sessionId)
    }

    public func requestGrid(_ ref: RemoteSessionRef, grid: TerminalGrid) {
        service.requestGrid(hubId: ref.hubId, sessionId: ref.sessionId, grid: grid)
    }

    public func sendInput(_ ref: RemoteSessionRef, data: Data) {
        service.sendInput(hubId: ref.hubId, sessionId: ref.sessionId, data: data)
    }

    /// Yapıştırılan görsel: main dışında relay'e sığacak şekilde kodlanıp hub'a gider.
    public func pasteImage(_ ref: RemoteSessionRef, rawImage: Data) {
        lastError = nil
        Task {
            let image = await Task.detached { RemoteImageEncoder.encode(rawImage) }.value
            guard let image else {
                lastError = "This image couldn't be sent to the hub."
                return
            }
            do {
                try await service.pasteImage(hubId: ref.hubId, sessionId: ref.sessionId, image: image)
            } catch RemoteControllerError.failed("unknown_action") {
                lastError = "Update Lumi on the hub to paste images."
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    public func viewMode(_ ref: RemoteSessionRef) -> RemoteSessionViewMode {
        // Ham terminal varsayılandır (kullanıcı kararı 2026-11-06); chat başlıktan seçilir.
        viewModes[ref] ?? .terminal
    }

    public func setViewMode(_ mode: RemoteSessionViewMode, for ref: RemoteSessionRef) {
        viewModes[ref] = mode
    }

    /// Claude terminalinin chat durumu. Oturum başına bir tane tutulur: terminaller arasında
    /// gidip gelince liste kalır, yeniden açılışta yalnız eksikler istenir (karar 130).
    public func chatSession(_ ref: RemoteSessionRef) -> RemoteChatSession {
        if let existing = chatSessions[ref] { return existing }
        let session = RemoteChatSession(ref: ref, service: service)
        chatSessions[ref] = session
        return session
    }

    public func dismissError() {
        lastError = nil
    }

    // MARK: - Olaylar

    private func apply(_ event: RemoteControllerEvent) {
        switch event {
        case .directoryStateChanged(let state):
            directoryState = state
        case .directoryIssueChanged(let issue):
            directoryIssue = issue
        case .hubsChanged(let list):
            hubs = list
        case .linkChanged(let hubId, let state):
            links[hubId] = state
            if state == .disconnected {
                snapshots[hubId] = nil
                dropChatSessions { $0.hubId == hubId }
            }
        case .snapshotChanged(let hubId, let snapshot):
            snapshots[hubId] = snapshot
            if links[hubId] == .connected {
                dropChatSessions { $0.hubId == hubId && snapshot.session($0.sessionId) == nil }
            }
            // Seçili terminal hub'da kapandıysa seçimi bırak.
            if let selected = selectedSession, selected.hubId == hubId,
               links[hubId] == .connected, snapshot.session(selected.sessionId) == nil {
                selectedSession = nil
            }
        }
    }

    private func dropChatSessions(where matches: (RemoteSessionRef) -> Bool) {
        for ref in chatSessions.keys where matches(ref) {
            chatSessions.removeValue(forKey: ref)?.stop()
        }
    }

    /// Hata → kullanıcıya gösterilen kısa metin (Lumi arayüzü İngilizcedir).
    public static func describe(_ error: Error) -> String {
        switch error as? RemoteControllerError {
        case .notConnected: return "Not connected to this hub."
        case .timedOut: return "The hub did not answer in time."
        case .failed(let detail): return "The hub refused: \(detail)"
        case nil: return "\(error)"
        }
    }

    /// Ret nedeni → kullanıcıya gösterilen kısa metin.
    public static func describeRejection(_ reason: String) -> String {
        switch reason {
        case "wrong_password": return "Wrong password."
        case "locked": return "Too many wrong passwords. Try again in a minute."
        case "password_required": return "Enter the hub's password."
        case "hub_not_ready": return "The hub has no password set."
        case "revoked": return "The hub disconnected all controllers."
        case "no_server": return "Connect to a server in This Mac first."
        case RemoteServerIssue.unauthorized.rawValue: return RemoteServerIssue.unauthorized.message
        case RemoteServerIssue.tokenRevoked.rawValue: return RemoteServerIssue.tokenRevoked.message
        case RemoteServerIssue.networkNotAllowed.rawValue: return RemoteServerIssue.networkNotAllowed.message
        default: return "Connection refused (\(reason))."
        }
    }
}
