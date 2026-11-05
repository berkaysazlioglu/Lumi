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

/// Mac'ten Mac'e remote'un controller tarafının UI köprüsü (docs/design/08):
/// hub listesi, bağlantı durumları, hub anlık görüntüleri ve Remote route'undaki seçim.
@Observable @MainActor
public final class RemoteControllerStore {
    public private(set) var directoryState: RemoteConnectionState
    public private(set) var hubs: [RemoteHubInfo]
    public private(set) var links: [String: RemoteHubLinkState] = [:]
    public private(set) var snapshots: [String: RemoteHubSnapshot] = [:]
    /// Ağaçta açık olan hub.
    public var selectedHubId: String?
    /// Sağ sütunda aynası gösterilen terminal.
    public var selectedSession: RemoteSessionRef?
    /// Son başarısız eylemin kullanıcıya gösterilecek açıklaması.
    public private(set) var lastError: String?

    private let service: any RemoteControllerServicing
    private var consumeTask: Task<Void, Never>?

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

    public func configure(relayUrl: String, networkToken: String, identity: RemoteControllerIdentity) {
        service.configure(relayUrl: relayUrl, networkToken: networkToken, identity: identity)
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
            if let sessionId = try await service.startSession(hubId: hubId, checkoutPath: checkoutPath, kind: kind) {
                select(RemoteSessionRef(hubId: hubId, sessionId: sessionId))
            }
        } catch {
            lastError = Self.describe(error)
        }
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

    public func sendInput(_ ref: RemoteSessionRef, data: Data) {
        service.sendInput(hubId: ref.hubId, sessionId: ref.sessionId, data: data)
    }

    public func dismissError() {
        lastError = nil
    }

    // MARK: - Olaylar

    private func apply(_ event: RemoteControllerEvent) {
        switch event {
        case .directoryStateChanged(let state):
            directoryState = state
        case .hubsChanged(let list):
            hubs = list
        case .linkChanged(let hubId, let state):
            links[hubId] = state
            if state == .disconnected { snapshots[hubId] = nil }
        case .snapshotChanged(let hubId, let snapshot):
            snapshots[hubId] = snapshot
            // Seçili terminal hub'da kapandıysa seçimi bırak.
            if let selected = selectedSession, selected.hubId == hubId,
               links[hubId] == .connected, snapshot.session(selected.sessionId) == nil {
                selectedSession = nil
            }
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
        case "no_network": return "Join a network first."
        default: return "Connection refused (\(reason))."
        }
    }
}
