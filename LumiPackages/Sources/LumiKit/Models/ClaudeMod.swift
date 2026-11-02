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

    /// Config'de kaydı olmayan mod açıktır — klasöre konan mod kullanılmak
    /// içindir; Lumi'nin kendi modları da varsayılan açık gelir.
    public static func isEnabled(_ modID: String, in config: AppConfig) -> Bool {
        config.claudeMods[modID] ?? true
    }

    /// Yeni terminallerin `CLAUDE_CODE_PLUGIN_DIRS`'ine yazılacak yollar.
    public static func enabledPaths(_ mods: [ClaudeMod], config: AppConfig) -> [String] {
        mods.filter { isEnabled($0.id, in: config) }.map(\.path)
    }
}
