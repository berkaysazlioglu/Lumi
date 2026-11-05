import Foundation

/// Platform path çözümlemesi (karar 9).
/// Prod: `~/.lumi`; dev: `~/.lumi-dev`. Prod'da yeni dizin yoksa legacy
/// `~/.pulpo` → `~/.ai-orchestrator` yerinde kullanılır (migration değil).
public struct LumiPaths: Sendable {
    public enum Mode: Sendable, Equatable {
        case production
        case development
    }

    public let mode: Mode
    public let configDir: URL
    public let tempDir: URL

    public var configFile: URL { configDir.appendingPathComponent("config.json") }
    public var uiStateFile: URL { configDir.appendingPathComponent("ui-state.json") }
    public var remoteFile: URL { configDir.appendingPathComponent("remote.json") }

    /// Yönetilen Claude hesaplarının auth kökü (karar 56). Hesap başına
    /// `<id>/auth/` altında yalnız `oauth-account.json` durur; token'lar
    /// Keychain'dedir.
    public var claudeAccountsDir: URL { configDir.appendingPathComponent("claude-accounts") }
    /// Hızlı komutların çalıştırılan, çözülmüş script'leri (karar 92).
    public var quickCommandsDir: URL { configDir.appendingPathComponent("quick-commands") }
    /// Orchestrator Claude'unun çalışma dizini (karar 114): hiçbir projenin
    /// `CLAUDE.md`'si yüklenmez, transkriptler projelerin Agent History'sine
    /// karışmaz.
    public var orchestratorDir: URL { configDir.appendingPathComponent("orchestrator") }
    /// Isolated Codex homes: `<id>/home/auth.json`.
    public var codexAccountsDir: URL { configDir.appendingPathComponent("codex-accounts") }
    /// Lumi terminallerindeki Claude'a yüklenen modlar (karar 142): `<id>/`
    /// başına bir Claude Code plugin klasörü.
    public var claudeModsDir: URL { configDir.appendingPathComponent("mods") }

    /// Config dizinini geçersiz kılan ortam değişkeni (mutlak yol, `~` açılır). Aynı Mac'te
    /// birbirine karışmayan birden çok Lumi koşturmak içindir — örn. Mac'ten Mac'e remote'u
    /// (karar 143) tek makinede hub + controller olarak denemek; `.app`'e Info.plist
    /// `LSEnvironment` ile verilir. Boşsa mod'un varsayılan dizini kullanılır.
    public static let configDirectoryVariable = "LUMI_CONFIG_DIR"

    /// Uygulamanın kendi yolları: `LUMI_CONFIG_DIR` varsa o dizin, yoksa mod'un dizini.
    public static func app(
        mode: Mode,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LumiPaths {
        let raw = environment[configDirectoryVariable]?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !raw.isEmpty else { return LumiPaths(mode: mode) }
        let expanded = (raw as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return LumiPaths(mode: mode) }
        return LumiPaths(mode: mode, configDirectoryOverride: URL(fileURLWithPath: expanded, isDirectory: true))
    }

    public init(
        mode: Mode,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory()),
        fileManager: FileManager = .default,
        configDirectoryOverride: URL? = nil
    ) {
        self.mode = mode
        if let configDirectoryOverride {
            self.configDir = configDirectoryOverride
            self.tempDir = temporaryDirectory.appendingPathComponent("lumi-" + configDirectoryOverride.lastPathComponent)
            return
        }
        switch mode {
        case .development:
            self.configDir = homeDirectory.appendingPathComponent(".lumi-dev")
            self.tempDir = temporaryDirectory.appendingPathComponent("lumi-dev")
        case .production:
            let primary = homeDirectory.appendingPathComponent(".lumi")
            if fileManager.fileExists(atPath: primary.path) {
                self.configDir = primary
            } else {
                let legacyCandidates = [".pulpo", ".ai-orchestrator"]
                    .map { homeDirectory.appendingPathComponent($0) }
                self.configDir = legacyCandidates.first {
                    fileManager.fileExists(atPath: $0.path)
                } ?? primary
            }
            self.tempDir = temporaryDirectory.appendingPathComponent("lumi")
        }
    }

    /// Constructor'daki `mkdir -p` semantiğinin karşılığı.
    public func ensureDirectoriesExist(fileManager: FileManager = .default) throws {
        for directory in [configDir, tempDir] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
