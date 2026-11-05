import Foundation

/// Relay istemcisinin servis sınırı. Implementasyon LumiRemote'ta;
/// LumiUI yalnız bu protokolü (RemoteStore üzerinden) görür.
@MainActor
public protocol RemoteServicing: AnyObject, Sendable {
    var state: RemoteConnectionState { get }
    var currentConfig: RemoteConfig { get }
    /// Config'i günceller, diske yazar; enabled değiştiyse bağlantıyı açar/kapar.
    func updateConfig(_ mutate: @Sendable (inout RemoteConfig) -> Void) async
    /// Yeni token üretip kaydeder ve (bağlıysa) yeniden bağlanır.
    func regenerateToken() async
    func start() async
    func stop()
    func events() -> AsyncStream<RemoteEvent>

    // MARK: Hub (docs/design/08) — bu Mac'in Mac'ten Mac'e ağda paylaşılması

    /// Keychain'de hub şifresi var mı (paylaşmanın ön koşulu).
    var hasHubPassword: Bool { get }
    /// Listede görünen ad: verilen ad, yoksa bilgisayar adı.
    var effectiveHubName: String { get }
    func setHubEnabled(_ enabled: Bool) async
    func setHubName(_ name: String) async
    func setHubPassword(_ password: String) async throws
    func removeHubPassword() async throws
    func disconnectAllControllers() async
    func createNetwork() async
    /// Ağ token'ı geçersizse (kısa / boşluklu) `false`.
    func joinNetwork(_ token: String) async -> Bool
    func leaveNetwork() async
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
    func createNetwork() async {}
    func joinNetwork(_ token: String) async -> Bool { false }
    func leaveNetwork() async {}
}
