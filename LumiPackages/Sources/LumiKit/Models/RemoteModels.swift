import Foundation

/// `~/.lumi/remote.json` şeması (Lumi Remote tasarımı §7). config.json'dan
/// bilinçli olarak ayrı dosya — karar 9 gereği mevcut format değişmez.
///
/// `enabled`/`token` telefon kanalınındır. Hub alanları (docs/design/08) additive'dir:
/// `networkToken` Mac'ten Mac'e ağın token'ı, `hubEnabled` bu Mac'in hub olarak
/// paylaşılması, `hubId` kurulum başına kalıcı kimlik, `hubName` listede görünen ad
/// (boşsa bilgisayar adı). Hub şifresi ve `hubKey` gizlidir; Keychain'de durur.
public struct RemoteConfig: Sendable, Equatable {
    public var enabled: Bool
    public var relayUrl: String
    public var token: String
    public var networkToken: String
    public var hubEnabled: Bool
    public var hubId: String
    public var hubName: String

    public static let defaults = RemoteConfig(
        enabled: false,
        relayUrl: "wss://lumi-relay-production.up.railway.app",
        token: ""
    )

    public init(
        enabled: Bool,
        relayUrl: String,
        token: String,
        networkToken: String = "",
        hubEnabled: Bool = false,
        hubId: String = "",
        hubName: String = ""
    ) {
        self.enabled = enabled
        self.relayUrl = relayUrl
        self.token = token
        self.networkToken = networkToken
        self.hubEnabled = hubEnabled
        self.hubId = hubId
        self.hubName = hubName
    }
}

/// Bu Mac hub iken ona bağlı bir controller (relay bağlantı kimliği + controller'ın adı).
public struct RemoteHubController: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum RemoteConnectionState: String, Sendable, Equatable {
    case disconnected
    case connecting
    case connected
}

public enum RemoteEvent: Sendable, Equatable {
    /// Telefon kanalının bağlantı durumu.
    case stateChanged(RemoteConnectionState)
    /// Hub kanalının bağlantı durumu (docs/design/08).
    case hubStateChanged(RemoteConnectionState)
    /// Hub'a bağlı controller'lar değişti.
    case hubControllersChanged([RemoteHubController])
    /// `remote.json` değişti (ağ token'ı, hub ayarları…) — controller kendini yeniden kurar.
    case configChanged(RemoteConfig)
}
