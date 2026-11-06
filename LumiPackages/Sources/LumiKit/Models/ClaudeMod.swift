import Foundation

/// Lumi terminallerindeki Claude Code'a yüklenen bir mod (karar 142): mod
/// klasöründeki (`~/.lumi/mods/<id>/`) bir Claude Code plugin'i.
public struct ClaudeMod: Sendable, Equatable, Identifiable {
    /// Klasör adı — açık/kapalı durumu config'de bununla tutulur.
    public let id: String
    /// `plugin.json` `name`'i; yoksa klasör adı.
    public let name: String
    public let description: String?
    public let version: String?
    /// Mod klasörünün mutlak yolu.
    public let path: String
    /// Lumi'nin kendi yazdığı (ve güncellediği) mod mu.
    public let isBundled: Bool

    public init(
        id: String,
        name: String,
        description: String? = nil,
        version: String? = nil,
        path: String,
        isBundled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.path = path
        self.isBundled = isBundled
    }
}

/// Modların terminale nasıl iletildiğinin saf kuralları (karar 142).
public enum ClaudeMods {
    /// Claude Code'un `--plugin-dir` eşdeğeri ortam değişkeni: `:` ile ayrılmış
    /// mutlak klasör yolları.
    public static let pluginDirsVariable = "CLAUDE_CODE_PLUGIN_DIRS"

    /// Config'de kaydı olmayan mod: Lumi'ninki açık, kullanıcınınki kapalı —
    /// klasöre dosya bırakabilen her süreç (ör. bir ajan) kendi kodunu sonraki
    /// her claude'a onaysız yükletemesin; kullanıcının modu anahtarla açılır.
    public static func isEnabled(_ mod: ClaudeMod, in config: AppConfig) -> Bool {
        config.claudeMods[mod.id] ?? mod.isBundled
    }

    /// Yeni terminallerin `CLAUDE_CODE_PLUGIN_DIRS`'ine yazılacak yollar.
    public static func enabledPaths(_ mods: [ClaudeMod], config: AppConfig) -> [String] {
        mods.filter { isEnabled($0, in: config) }.map(\.path)
    }

    /// Hub olarak paylaşılan Mac'te kapalı tutulan Lumi modları (karar 143 ek):
    /// `image-preview` terminale kitty görsel verisi basar — controller'lara relay
    /// üzerinden giderdi. Hepsi Lumi'nin modudur (kayıtsızken açık).
    public static let hubIncompatibleModIDs: Set<String> = ["image-preview"]

    /// Paylaşım açılınca modları kapatıp önceki durumlarını saklar; kapanınca geri
    /// yükler. İdempotent: zaten saklanmışsa ya da saklanacak bir şey yoksa dokunmaz.
    public static func applyingHubSharing(_ isSharing: Bool, to config: AppConfig) -> AppConfig {
        var config = config
        if isSharing {
            for id in hubIncompatibleModIDs.sorted() where config.hubSuspendedClaudeMods[id] == nil {
                config.hubSuspendedClaudeMods[id] = config.claudeMods[id] ?? true
                config.claudeMods[id] = false
            }
        } else {
            for (id, previous) in config.hubSuspendedClaudeMods {
                config.claudeMods[id] = previous
            }
            config.hubSuspendedClaudeMods = [:]
        }
        return config
    }
}
