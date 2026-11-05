import Foundation
import LumiKit

/// Relay'deki iki kanal: telefonun token'lı odası ve Mac'ten Mac'e hub kanalı (docs/design/08).
enum RemoteChannel: String, Sendable {
    case mobile
    case hub
}

/// Bu Mac'in hub olarak paylaşılması (docs/design/08-mac-remote.md, "Hub tarafı").
extension RemoteService {
    /// Listede görünen ad: kullanıcının verdiği ad, yoksa bilgisayar adı.
    var effectiveHubName: String {
        let trimmed = currentConfig.hubName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Host.current().localizedName ?? "Mac"
    }

    /// Hub kanalının `hello`'su; paylaşım kapalıysa ya da ağ token'ı / şifre / `hubKey`
    /// eksikse `nil` (kanal açılmaz). `hasHubPassword`'ü de tazeler.
    func hubHelloIfReady() async -> [String: Any]? {
        guard let hubSecrets else { return nil }
        hasHubPassword = await hubSecrets.passwordRecord().value != nil
        let config = currentConfig
        guard config.hubEnabled, !config.networkToken.isEmpty, hasHubPassword else { return nil }
        guard let hubKey = await hubSecrets.hubKey() else {
            rlog("hub: hubKey okunamadı — hub kanalı açılmıyor")
            return nil
        }
        return [
            "role": "hub",
            "network": config.networkToken,
            "hubId": config.hubId,
            "hubKey": hubKey,
            "name": effectiveHubName,
        ]
    }

    /// Relay'in ilettiği bağlanma isteğini şifreyle doğrulayıp `attach_result` döner.
    func handleAttachRequest(_ payload: [String: Any]) async {
        guard let requestId = payload["requestId"] as? String,
              let connectionId = payload["connectionId"] as? String else { return }
        let controllerId = payload["controllerId"] as? String ?? connectionId
        let name = (payload["controllerName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Mac"
        let password = payload["password"] as? String ?? ""
        let error = await verifyAttach(controllerId: controllerId, password: password)
        var result: [String: Any] = ["requestId": requestId, "ok": error == nil]
        if let error { result["error"] = error }
        rlog("hub: attach \(error == nil ? "kabul" : "ret (\(error!))") controller=\(name)")
        await sendOnHub(type: "attach_result", payload: result)
        guard error == nil else { return }
        setHubControllers(hubControllers.filter { $0.id != connectionId }
            + [RemoteHubController(id: connectionId, name: name)])
    }

    /// `nil` = kabul; aksi halde relay'in controller'a ileteceği ret nedeni.
    private func verifyAttach(controllerId: String, password: String) async -> String? {
        let now = turnClock()
        if attemptLimiter.isLocked(controllerId, now: now) { return "locked" }
        guard let hubSecrets, case .found(let record) = await hubSecrets.passwordRecord() else {
            return "hub_not_ready"
        }
        // PBKDF2 CPU işidir (bloklayan bekleme değil); ana aktörü tutmasın diye ayrı task'ta koşar.
        let ok = await Task.detached { HubPasswordHash.verify(password: password, record: record) }.value
        if ok {
            attemptLimiter.recordSuccess(controllerId)
            return nil
        }
        attemptLimiter.recordFailure(controllerId, now: now)
        return "wrong_password"
    }

    // MARK: - Ayarlar (Remote route'u — Faz 4)

    /// Yeni hub şifresi. Bağlı controller'lar düşer; yeniden bağlanmak yeni şifre ister.
    public func setHubPassword(_ password: String) async throws {
        guard let hubSecrets else { throw RemoteHubError.notConfigured }
        try await hubSecrets.setPassword(password)
        await revokeControllers()
        await restart()
    }

    /// Şifreyi siler; şifresiz hub paylaşılamadığı için paylaşım da kapanır.
    public func removeHubPassword() async throws {
        guard let hubSecrets else { throw RemoteHubError.notConfigured }
        await revokeControllers()
        try await hubSecrets.removePassword()
        await updateConfig { $0.hubEnabled = false }
        await restart()
    }

    /// Bağlı bütün controller'ları düşürür (`Disconnect All`).
    public func disconnectAllControllers() async {
        await revokeControllers()
    }

    public func setHubEnabled(_ enabled: Bool) async {
        await updateConfig { $0.hubEnabled = enabled }
    }

    public func setHubName(_ name: String) async {
        await updateConfig { $0.hubName = name }
    }

    /// Yeni ağ token'ı üretir (`Create Network`).
    public func createNetwork() async {
        let token = generateToken()
        await updateConfig { $0.networkToken = token }
    }

    /// Başka bir Mac'in ağ token'ına katılır (`Join Network…`). Relay'in alt sınırı 16 karakterdir.
    @discardableResult
    public func joinNetwork(_ token: String) async -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 16, !trimmed.contains(where: \.isWhitespace) else { return false }
        await updateConfig { $0.networkToken = trimmed }
        return true
    }

    public func leaveNetwork() async {
        await updateConfig {
            $0.networkToken = ""
            $0.hubEnabled = false
        }
    }

    private func revokeControllers() async {
        await sendOnHub(type: "revoke_controllers", payload: [:])
        dropHubControllers(where: { _ in true })
    }
}
