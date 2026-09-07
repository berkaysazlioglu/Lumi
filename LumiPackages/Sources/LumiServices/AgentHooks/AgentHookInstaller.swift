import Foundation
import LumiKit

/// Yönetilen hook script'lerini yazar ve Claude / Codex ayar dosyalarına
/// kaydeder (karar 45). Idempotent: içerik aynıysa hiçbir dosyaya dokunmaz.
///
/// Güvenlik sınırları:
/// - Kullanıcı dosyası ayrıştırılamıyorsa ASLA üzerine yazılmaz (`failed`).
/// - Sağlayıcının ev dizini (`~/.claude`, `~/.codex`) yoksa CLI kurulu
///   sayılmaz → `skipped`; Lumi başkasının dizinini yaratmaz.
/// - Yazımlar atomiktir; script dizini 0700, script'ler 0755.
public struct AgentHookInstaller: AgentHookInstalling {
    public let homeDirectory: URL
    /// `~/.lumi/hooks` (dev'de `~/.lumi-dev/hooks`).
    public let scriptDirectory: URL
    /// `FileManager.default` thread-safe'tir; Sendable damgası yoktur.
    private var fileManager: FileManager { .default }

    public init(homeDirectory: URL, scriptDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.scriptDirectory = scriptDirectory
    }

    /// `LumiPaths` üzerinden standart yerleşim.
    public init(paths: LumiPaths, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.init(
            homeDirectory: homeDirectory,
            scriptDirectory: paths.configDir.appendingPathComponent(AgentHookScript.directoryName)
        )
    }

    var claudeSettingsFile: URL { homeDirectory.appendingPathComponent(".claude/settings.json") }
    var codexDirectory: URL { homeDirectory.appendingPathComponent(".codex") }
    var codexHooksFile: URL { codexDirectory.appendingPathComponent("hooks.json") }
    var codexConfigFile: URL { codexDirectory.appendingPathComponent("config.toml") }

    func scriptPath(for provider: AgentProvider) -> String {
        scriptDirectory.appendingPathComponent(AgentHookScript.fileName(for: provider)).path
    }

    // MARK: - AgentHookInstalling

    public func install() async -> [AgentHookInstallResult] {
        [installClaude(), installCodex()]
    }

    public func uninstall() async -> [AgentHookInstallResult] {
        let results = [uninstallClaude(), uninstallCodex()]
        try? fileManager.removeItem(at: scriptDirectory)
        return results
    }

    // MARK: - Claude

    private func installClaude() -> AgentHookInstallResult {
        let claudeDir = claudeSettingsFile.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: claudeDir.path) else {
            return AgentHookInstallResult(provider: .claude, outcome: .skipped(reason: "Claude Code not installed"))
        }
        do {
            let scriptChanged = try writeScript(for: .claude)
            let root = try readJSONObject(at: claudeSettingsFile)
            let command = AgentHookScript.managedCommand(scriptPath: scriptPath(for: .claude), provider: .claude)
            let (next, changed) = ClaudeHookSettings.applyManaged(to: root, command: command, isStale: isStaleCommand)
            if changed { try writeJSONObject(next, to: claudeSettingsFile) }
            return AgentHookInstallResult(provider: .claude, outcome: changed || scriptChanged ? .installed : .unchanged)
        } catch {
            return AgentHookInstallResult(provider: .claude, outcome: .failed(detail: error.localizedDescription))
        }
    }

    private func uninstallClaude() -> AgentHookInstallResult {
        guard fileManager.fileExists(atPath: claudeSettingsFile.path) else {
            return AgentHookInstallResult(provider: .claude, outcome: .unchanged)
        }
        do {
            let root = try readJSONObject(at: claudeSettingsFile)
            let (next, changed) = ClaudeHookSettings.removeManaged(from: root)
            if changed { try writeJSONObject(next, to: claudeSettingsFile) }
            return AgentHookInstallResult(provider: .claude, outcome: changed ? .removed : .unchanged)
        } catch {
            return AgentHookInstallResult(provider: .claude, outcome: .failed(detail: error.localizedDescription))
        }
    }

    // MARK: - Codex

    private func installCodex() -> AgentHookInstallResult {
        guard fileManager.fileExists(atPath: codexDirectory.path) else {
            return AgentHookInstallResult(provider: .codex, outcome: .skipped(reason: "Codex not installed"))
        }
        do {
            let scriptChanged = try writeScript(for: .codex)
            let root = try readJSONObject(at: codexHooksFile)
            let command = AgentHookScript.managedCommand(scriptPath: scriptPath(for: .codex), provider: .codex)
            let applied = CodexHookSettings.applyManaged(to: root, command: command)
            if applied.changed { try writeJSONObject(applied.root, to: codexHooksFile) }

            let hooksPath = codexDirectory.resolvingSymlinksInPath().appendingPathComponent("hooks.json").path
            let entries = CodexHookSettings.events.compactMap { event -> CodexHookTrust.Entry? in
                guard let label = CodexHookTrust.eventLabels[event], let group = applied.groupIndex[event] else { return nil }
                return CodexHookTrust.Entry(
                    key: CodexHookTrust.key(hooksPath: hooksPath, label: label, group: group),
                    hash: CodexHookTrust.trustedHash(label: label, command: command, timeoutSeconds: CodexHookSettings.timeoutSeconds)
                )
            }
            let trustChanged = try applyTrust(desired: entries, ownedHashes: Set(entries.map(\.hash)))
            let changed = applied.changed || trustChanged || scriptChanged
            return AgentHookInstallResult(provider: .codex, outcome: changed ? .installed : .unchanged)
        } catch {
            return AgentHookInstallResult(provider: .codex, outcome: .failed(detail: error.localizedDescription))
        }
    }

    private func uninstallCodex() -> AgentHookInstallResult {
        guard fileManager.fileExists(atPath: codexHooksFile.path) else {
            return AgentHookInstallResult(provider: .codex, outcome: .unchanged)
        }
        do {
            let root = try readJSONObject(at: codexHooksFile)
            let command = AgentHookScript.managedCommand(scriptPath: scriptPath(for: .codex), provider: .codex)
            let (next, changed) = CodexHookSettings.removeManaged(from: root)
            if changed { try writeJSONObject(next, to: codexHooksFile) }
            // Güven kayıtları: bizim hash'lerimizi taşıyan tüm bölümler düşer.
            let owned = Set(CodexHookTrust.eventLabels.values.map {
                CodexHookTrust.trustedHash(label: $0, command: command, timeoutSeconds: CodexHookSettings.timeoutSeconds)
            })
            let trustChanged = try applyTrust(desired: [], ownedHashes: owned)
            return AgentHookInstallResult(provider: .codex, outcome: changed || trustChanged ? .removed : .unchanged)
        } catch {
            return AgentHookInstallResult(provider: .codex, outcome: .failed(detail: error.localizedDescription))
        }
    }

    private func applyTrust(desired: [CodexHookTrust.Entry], ownedHashes: Set<String>) throws -> Bool {
        let source = fileManager.fileExists(atPath: codexConfigFile.path)
            ? try String(contentsOf: codexConfigFile, encoding: .utf8)
            : ""
        let (result, changed) = CodexConfigTomlEditor.apply(to: source, desired: desired, ownedHashes: ownedHashes)
        if changed { try result.write(to: codexConfigFile, atomically: true, encoding: .utf8) }
        return changed
    }

    // MARK: - Dosya yardımcıları

    /// Script'i yalnız içerik değiştiyse yazar; dönüş = yazıldı mı.
    private func writeScript(for provider: AgentProvider) throws -> Bool {
        try fileManager.createDirectory(
            at: scriptDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = URL(fileURLWithPath: scriptPath(for: provider))
        let content = AgentHookScript.posix(provider: provider)
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == content,
           (try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o755 {
            return false
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return true
    }

    /// Eski Lumi komutu: işaret ettiği script artık yok (taşınmış/silinmiş ev).
    private func isStaleCommand(_ command: String) -> Bool {
        guard let path = AgentHookScript.scriptPath(inManagedCommand: command) else { return true }
        return !fileManager.fileExists(atPath: path)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty || data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LumiError.configIOFailed(file: url.path, detail: "not a JSON object")
        }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (data + Data("\n".utf8)).write(to: url, options: .atomic)
    }
}
