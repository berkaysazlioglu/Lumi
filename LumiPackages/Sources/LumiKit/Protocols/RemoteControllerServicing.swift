import Foundation

/// Mac'ten Mac'e remote'un controller tarafı (docs/design/08): relay'deki hub
/// directory'sini izler, hub'lara şifreyle bağlanır ve onlardaki terminalleri sürer.
/// Implementasyon LumiRemote'ta (`RemoteControllerService`); UI `RemoteControllerStore`'u görür.
@MainActor
public protocol RemoteControllerServicing: AnyObject {
    var directoryState: RemoteConnectionState { get }
    var hubs: [RemoteHubInfo] { get }
    func linkState(_ hubId: String) -> RemoteHubLinkState
    func snapshot(_ hubId: String) -> RemoteHubSnapshot?

    /// Ağ token'ı / relay adresi değişti — directory bağlantısını yeniden kurar,
    /// token değiştiyse açık hub bağlantılarını kapatır. Boş token directory'yi kapatır.
    func configure(relayUrl: String, networkToken: String, identity: RemoteControllerIdentity)
    func stop()

    /// Hub'a bağlanır. `password` nil ise hatırlanan şifre (Keychain) kullanılır.
    func connect(hubId: String, password: String?, remember: Bool) async
    func disconnect(hubId: String)
    /// Bu hub için hatırlanan bir şifre var mı?
    func hasRememberedPassword(hubId: String) async -> Bool

    /// Terminal aynası: `subscribe` gönderir ve gelen scrollback/data parçalarını akıtır.
    /// Akış bitince (view kapandı) `unsubscribe` gönderilir.
    func terminalOutput(hubId: String, sessionId: String) -> AsyncStream<RemoteTerminalChunk>
    func sendInput(hubId: String, sessionId: String, data: Data)
    /// Yeni terminal; Claude ve shell için yeni terminalin kimliğini döner.
    func startSession(hubId: String, checkoutPath: String, kind: RemoteSessionKind) async throws -> String?
    func closeSession(hubId: String, sessionId: String) async throws

    func events() -> AsyncStream<RemoteControllerEvent>
}

/// Controller'ın relay'e kendini tanıttığı kimlik (hub tarafındaki listede görünür).
public struct RemoteControllerIdentity: Sendable, Equatable {
    public let controllerId: String
    public let name: String
    /// Bu Mac'in kendi hub kimliği — kendi hub'ı listede gösterilmez.
    public let ownHubId: String

    public init(controllerId: String, name: String, ownHubId: String) {
        self.controllerId = controllerId
        self.name = name
        self.ownHubId = ownHubId
    }
}
