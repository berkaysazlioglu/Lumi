import Foundation

/// Relay istemcisinin servis sınırı. Implementasyon LumiRemote'ta;
/// LumiUI yalnız bu protokolü (RemoteStore üzerinden) görür.
@MainActor
public protocol RemoteServicing: AnyObject, Sendable {
    var state: RemoteConnectionState { get }
    var currentConfig: RemoteConfig { get }
    /// Sunucunun kalıcı reddi (401 / 4006 / 4007, karar 146); yoksa `nil`.
    var serverIssue: RemoteServerIssue? { get }
    /// Config'i günceller, diske yazar; enabled değiştiyse bağlantıyı açar/kapar.
    func updateConfig(_ mutate: @Sendable (inout RemoteConfig) -> Void) async
    /// Yeni token üretip kaydeder ve (bağlıysa) yeniden bağlanır.
    func regenerateToken() async
    func start() async
    func stop()
    func events() -> AsyncStream<RemoteEvent>

    // MARK: Hub (docs/design/08) — bu Mac'in sunucuda paylaşılması

    /// Keychain'de hub şifresi var mı (paylaşmanın ön koşulu).
    var hasHubPassword: Bool { get }
    /// Listede görünen ad: verilen ad, yoksa bilgisayar adı.
    var effectiveHubName: String { get }
    func setHubEnabled(_ enabled: Bool) async
    func setHubName(_ name: String) async
    func setHubPassword(_ password: String) async throws
    func removeHubPassword() async throws
    func disconnectAllControllers() async
    /// Relay sunucusunun adresi + token'ı (karar 146); değişince kanallar yeniden kurulur.
    func setServer(url: String, token: String) async
}

/// Hub'ı olmayan istemciler (önizleme, test sahteleri) için no-op'lar.
public extension RemoteServicing {
    var hasHubPassword: Bool { false }
    var effectiveHubName: String { "Mac" }
    func setHubEnabled(_ enabled: Bool) async {}
    func setHubName(_ name: String) async {}
    func setHubPassword(_ password: String) async throws {}
    func removeHubPassword() async throws {}
    func disconnectAllControllers() async {}
    var serverIssue: RemoteServerIssue? { nil }
    func setServer(url: String, token: String) async {}
}
