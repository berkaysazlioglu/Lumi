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
    /// Yeni terminal; Claude ve shell için yeni terminalin kimliğini döner. Claude'da
    /// boş olmayan `prompt` ilk mesaj olarak gider.
    func startSession(hubId: String, checkoutPath: String, kind: RemoteSessionKind, prompt: String) async throws -> String?
    func closeSession(hubId: String, sessionId: String) async throws
    /// Metni terminale yazar; `submit` ise Enter da basılır.
    func sendText(hubId: String, sessionId: String, text: String, submit: Bool) async throws
    /// Terminalin içeriğini bir kez okur (aynayı etkilemez).
    func readTerminal(hubId: String, sessionId: String) async throws -> RemoteTerminalReading

    /// Claude terminalinin chat akışı (`subscribe` mode `chat`; `afterId` → yalnız o
    /// mesajdan sonrası). Akış bitince `unsubscribe{mode:chat}` gider; ayna etkilenmez.
    func chatEvents(hubId: String, sessionId: String, afterId: String?) -> AsyncStream<RemoteChatEvent>
    /// Chat'ten mesaj: hub metni PTY'ye yazar, kısa bir beklemeyle Enter basar.
    func sendChat(hubId: String, sessionId: String, text: String)
    /// İzin / soru kartını cevaplar (`prompt_respond`).
    func respondPrompt(hubId: String, sessionId: String, itemId: String, revision: Int, answer: RemotePromptAnswer)

    func events() -> AsyncStream<RemoteControllerEvent>
}

public extension RemoteControllerServicing {
    func startSession(hubId: String, checkoutPath: String, kind: RemoteSessionKind) async throws -> String? {
        try await startSession(hubId: hubId, checkoutPath: checkoutPath, kind: kind, prompt: "")
    }
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
