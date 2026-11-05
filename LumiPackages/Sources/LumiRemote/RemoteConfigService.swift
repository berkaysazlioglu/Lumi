import Foundation
import LumiKit

/// 32 bayt rastgele → base64url (43 karakter, padding'siz).
func generateToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max) }
    return Data(bytes).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// `remote.json` persistence'ı. ConfigService kalıbı: JSONSerialization +
/// ham-dict merge — bilinmeyen anahtarlar yazımda korunur (karar 9).
public actor RemoteConfigService {
    private let paths: LumiPaths

    public init(paths: LumiPaths) {
        self.paths = paths
    }

    public func load() -> RemoteConfig {
        guard let dict = readRaw() else { return .defaults }
        let defaults = RemoteConfig.defaults
        return RemoteConfig(
            enabled: dict["enabled"] as? Bool ?? defaults.enabled,
            relayUrl: dict["relayUrl"] as? String ?? defaults.relayUrl,
            token: dict["token"] as? String ?? defaults.token,
            networkToken: dict["networkToken"] as? String ?? defaults.networkToken,
            hubEnabled: dict["hubEnabled"] as? Bool ?? defaults.hubEnabled,
            hubId: dict["hubId"] as? String ?? defaults.hubId,
            hubName: dict["hubName"] as? String ?? defaults.hubName
        )
    }

    public func save(_ config: RemoteConfig) {
        var merged = readRaw() ?? [:]
        merged["enabled"] = config.enabled
        merged["relayUrl"] = config.relayUrl
        merged["token"] = config.token
        // Hub alanları (docs/design/08) — additive; eski Lumi bunları yok sayar.
        merged["networkToken"] = config.networkToken
        merged["hubEnabled"] = config.hubEnabled
        merged["hubId"] = config.hubId
        merged["hubName"] = config.hubName
        guard let data = try? JSONSerialization.data(
            withJSONObject: merged,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return }
        try? data.write(to: paths.remoteFile, options: .atomic)
    }

    /// Telefon token'ı ve hub kimliği boşsa üretip kaydeder; her durumda güncel config'i döner.
    public func ensureToken() -> RemoteConfig {
        var config = load()
        var changed = false
        if config.token.isEmpty {
            config.token = generateToken()
            changed = true
        }
        if config.hubId.isEmpty {
            config.hubId = UUID().uuidString
            changed = true
        }
        if changed { save(config) }
        return config
    }

    private func readRaw() -> [String: Any]? {
        guard let data = try? Data(contentsOf: paths.remoteFile),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else { return nil }
        return dict
    }
}
