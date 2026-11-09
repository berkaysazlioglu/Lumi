import Foundation

/// `~/.lumi/remote.json` şeması (Lumi Remote tasarımı §7). config.json'dan
/// bilinçli olarak ayrı dosya — karar 9 gereği mevcut format değişmez.
///
/// `relayUrl` + `serverToken` kullanıcının bağlandığı relay sunucusudur (karar 146,
/// docs/design/09): Lumi'ye adres gömülmez, ikisi de boş başlar. `enabled`/`token`
/// telefon kanalınındır (oda token'ı). Hub alanları (docs/design/08) additive'dir:
/// `hubEnabled` bu Mac'in hub olarak paylaşılması, `hubId` kurulum başına kalıcı
/// kimlik, `hubName` listede görünen ad (boşsa bilgisayar adı). Hub şifresi ve
/// `hubKey` gizlidir; Keychain'de durur. Eski `networkToken` anahtarı okunmaz
/// (sunucu tek ağdır) ama dosyada korunur.
public struct RemoteConfig: Sendable, Equatable {
    public var enabled: Bool
    public var relayUrl: String
    public var token: String
    public var serverToken: String
    public var hubEnabled: Bool
    public var hubId: String
    public var hubName: String

    public static let defaults = RemoteConfig(enabled: false, relayUrl: "", token: "")

    /// Karar 146'dan önceki gömülü varsayılan — okunurken boşa çevrilir.
    public static let legacyRelayUrl = "wss://lumi-relay-production.up.railway.app"

    public init(
        enabled: Bool,
        relayUrl: String,
        token: String,
        serverToken: String = "",
        hubEnabled: Bool = false,
        hubId: String = "",
        hubName: String = ""
    ) {
        self.enabled = enabled
        self.relayUrl = relayUrl
        self.token = token
        self.serverToken = serverToken
        self.hubEnabled = hubEnabled
        self.hubId = hubId
        self.hubName = hubName
    }

    /// Bağlanılacak sunucu; adres ya da token eksik/geçersizse `nil` (hiçbir kanal açılmaz).
    public var endpoint: RelayEndpoint? {
        RelayEndpoint(url: relayUrl, token: serverToken)
    }
}

/// Relay sunucusu: adres + server token'ı (karar 146). Token el sıkışmada
/// `Authorization: Bearer` olarak gider.
public struct RelayEndpoint: Sendable, Equatable {
    public let url: URL
    public let token: String

    public init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    /// `ws://` / `wss://` adres ve boş olmayan, boşluksuz token; değilse `nil`.
    public init?(url rawURL: String, token rawToken: String) {
        let address = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidAddress(address), !token.isEmpty, !token.contains(where: \.isWhitespace),
              let url = URL(string: address) else { return nil }
        self.init(url: url, token: token)
    }

    public static func isValidAddress(_ raw: String) -> Bool {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "wss" || scheme == "ws", let host = url.host, !host.isEmpty else { return false }
        return true
    }
}

/// Sunucunun bağlantıyı kalıcı olarak reddetme nedeni (karar 146). Bu durumlarda
/// yeniden bağlanma denenmez; kullanıcı adresi/token'ı düzeltince kanal yeniden kurulur.
public enum RemoteServerIssue: String, Sendable, Equatable {
    /// HTTP 401 — token yanlış ya da bu sunucuya ait değil.
    case unauthorized
    /// 4007 — token dashboard'dan iptal edildi.
    case tokenRevoked
    /// 4006 — bu ağın IP'si sunucunun allowlist'inde değil (yalnız hub/controller).
    case networkNotAllowed

    public var message: String {
        switch self {
        case .unauthorized: return "The server rejected the token. Check the server URL and token."
        case .tokenRevoked: return "This token was revoked on the server. Ask for a new one."
        case .networkNotAllowed: return "This network isn't on the server's IP allowlist. Connect from the office or VPN."
        }
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
    /// `remote.json` değişti (sunucu, hub ayarları…) — controller kendini yeniden kurar.
    case configChanged(RemoteConfig)
    /// Sunucu bağlantıyı kalıcı olarak reddetti; `nil` sorun giderildi (karar 146).
    case serverIssueChanged(RemoteServerIssue?)
}
