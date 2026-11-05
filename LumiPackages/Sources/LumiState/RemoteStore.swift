import Foundation
import LumiKit

/// RemoteServicing → UI köprüsü (servis→store AsyncStream, store→UI @Observable).
@Observable @MainActor
public final class RemoteStore {
    public private(set) var state: RemoteConnectionState
    public private(set) var config: RemoteConfig
    /// Hub kanalının durumu ve bağlı controller'lar (docs/design/08).
    public private(set) var hubState: RemoteConnectionState = .disconnected
    public private(set) var hubControllers: [RemoteHubController] = []

    private let service: any RemoteServicing
    private var consumeTask: Task<Void, Never>?

    public init(service: any RemoteServicing) {
        self.service = service
        self.state = service.state
        self.config = service.currentConfig
    }

    public func start() {
        guard consumeTask == nil else { return }
        let stream = service.events()
        consumeTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .stateChanged(let newState):
                    self.state = newState
                case .hubStateChanged(let newState):
                    self.hubState = newState
                case .hubControllersChanged(let controllers):
                    self.hubControllers = controllers
                case .configChanged:
                    break
                }
                self.config = self.service.currentConfig
            }
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        await service.updateConfig { $0.enabled = enabled }
        config = service.currentConfig
    }

    public func setRelayUrl(_ url: String) async {
        await service.updateConfig { $0.relayUrl = url }
        config = service.currentConfig
    }

    public func regenerateToken() async {
        await service.regenerateToken()
        config = service.currentConfig
    }

    // MARK: - Hub (docs/design/08)

    /// Keychain'de hub şifresi var mı — eylemlerden sonra servisten tazelenir.
    public var hasHubPassword: Bool { refreshTick >= 0 && service.hasHubPassword }
    public var hubDisplayName: String { refreshTick >= 0 ? service.effectiveHubName : "" }
    public var hasNetwork: Bool { !config.networkToken.isEmpty }
    /// Observation'ın servisten okunan değerleri yeniden okuması için sayaç.
    private var refreshTick = 0

    public func setHubEnabled(_ enabled: Bool) async {
        await service.setHubEnabled(enabled)
        refresh()
    }

    public func setHubName(_ name: String) async {
        await service.setHubName(name)
        refresh()
    }

    /// Hata kullanıcıya gösterilmek üzere fırlatılır (Keychain yazımı başarısız olabilir).
    public func setHubPassword(_ password: String) async throws {
        defer { refresh() }
        try await service.setHubPassword(password)
    }

    public func removeHubPassword() async throws {
        defer { refresh() }
        try await service.removeHubPassword()
    }

    public func disconnectAllControllers() async {
        await service.disconnectAllControllers()
    }

    public func createNetwork() async {
        await service.createNetwork()
        refresh()
    }

    public func joinNetwork(_ token: String) async -> Bool {
        let ok = await service.joinNetwork(token)
        refresh()
        return ok
    }

    public func leaveNetwork() async {
        await service.leaveNetwork()
        refresh()
    }

    private func refresh() {
        config = service.currentConfig
        refreshTick &+= 1
    }

    public var pairingString: String {
        func encode(_ s: String) -> String {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: ":/")
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }
        return "lumi-remote://pair?url=\(encode(config.relayUrl))&token=\(encode(config.token))"
    }
}
