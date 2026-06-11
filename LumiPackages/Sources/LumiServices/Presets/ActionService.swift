import Foundation
import LumiKit

/// Action store + engine + AI akışları (spec/13 §3).
///
/// Seed asimetrisi (persona'nın TERSİ): hedef dosyada `modified_at` varsa
/// default EZİLMEZ (kullanıcı düzenlemesi korunur, id yine default işaretli);
/// parse-bozuk dosya ezilir; deprecated default'lar silinir. Default silinirse
/// watcher reseed'le anında geri getirir — default'lar silinemez, düzenlenir.
public actor ActionService: ActionServicing {
    static let maxHistoryPerAction = 20
    static let deprecatedDefaultFiles = [
        "new-terminal.yaml", "create-action.yaml", "git-pull.yaml",
        "install-deps.yaml", "install-plugins.yaml",
    ]

    private let userDirectory: URL
    private let seedDirectory: URL?
    private let config: any ConfigServicing
    private let engine: ActionEngine
    private let commandBuilder: AgentCommandBuilder
    private let broadcaster = EventBroadcaster<Void>()
    private let watchQueue = DispatchQueue(label: "lumi.actions.watch", qos: .utility)

    private var defaultIDs: Set<String> = []
    private var userActions: [Action] = []
    private var projectActions: [String: [Action]] = [:]
    private var watchers: [String: DirectoryWatcher] = [:]
    /// Backup diff'i için kullanıcı dizini dosya damgaları (watcher dosya adı vermez)
    private var fileStamps: [String: Date] = [:]
    private var userLoaded = false

    private var historyDirectory: URL {
        userDirectory.appendingPathComponent(".history")
    }

    public init(
        paths: LumiPaths,
        seedDirectory: URL?,
        terminal: any TerminalServicing,
        config: any ConfigServicing
    ) {
        self.userDirectory = paths.actionsDir
        self.seedDirectory = seedDirectory
        self.config = config
        self.engine = ActionEngine(terminal: terminal)
        self.commandBuilder = AgentCommandBuilder(tempDirectory: paths.tempDir)
    }

    // MARK: - Seed (spec/13 §3.2 — akıllı, persona'dan farklı)

    public func seedDefaults() {
        try? FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)

        for deprecated in Self.deprecatedDefaultFiles {
            try? FileManager.default.removeItem(
                at: userDirectory.appendingPathComponent(deprecated)
            )
        }

        if let seedDirectory {
            for seed in Self.yamlFiles(in: seedDirectory) {
                guard let seedContent = try? String(contentsOf: seed, encoding: .utf8) else { continue }
                if let id = PresetCodec.actionID(in: seedContent) {
                    defaultIDs.insert(id)
                }
                let target = userDirectory.appendingPathComponent(seed.lastPathComponent)
                if let existing = try? String(contentsOf: target, encoding: .utf8),
                   PresetCodec.decodeAction(existing, scope: .user) != nil,
                   PresetCodec.hasModifiedAt(existing) {
                    continue // kullanıcı düzenlemesi korunur
                }
                try? seedContent.write(to: target, atomically: true, encoding: .utf8)
            }
        }

        refreshFileStamps() // seed yazımları backup üretmesin
        reloadUser()
        ensureUserWatcher()
    }

    // MARK: - Listeleme / scope merge

    public func actions(projectPath: String?) -> [Action] {
        loadUserIfNeeded()
        var result = userActions
        if let projectPath {
            let project = loadProjectIfNeeded(projectPath)
            let projectIDs = Set(project.map(\.id))
            result = result.filter { !projectIDs.contains($0.id) } + project
        }
        return result
    }

    public func events() -> AsyncStream<Void> {
        broadcaster.stream()
    }

    // MARK: - Çalıştırma (spec/13 §3.10)

    public func execute(actionID: String, repoPath: String) async throws -> TerminalMeta {
        guard let action = actions(projectPath: repoPath).first(where: { $0.id == actionID }) else {
            throw LumiError.underlying(domain: "action", message: "Action not found: \(actionID)")
        }
        let provider: AgentProvider
        if let explicit = action.provider {
            provider = explicit
        } else {
            provider = (await config.config()).aiProvider
        }
        return try await engine.execute(
            action, repoPath: repoPath, provider: provider, builder: commandBuilder
        )
    }

    // MARK: - Silme (spec/13 §3.5 — id ALANINA göre, dosya adına değil)

    public func delete(actionID: String, scope: PresetScope, projectPath: String?) throws {
        let directory: URL
        switch scope {
        case .user:
            directory = userDirectory
        case .project:
            guard let projectPath else {
                throw LumiError.fileOperationFailed(path: actionID, detail: "project path required")
            }
            directory = URL(fileURLWithPath: projectPath).appendingPathComponent(".lumi/actions")
        }
        guard let file = Self.findFile(withActionID: actionID, in: directory) else {
            throw LumiError.fileOperationFailed(path: actionID, detail: "action file not found")
        }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            throw LumiError.fileOperationFailed(path: actionID, detail: error.localizedDescription)
        }
        if scope == .user {
            refreshFileStamps()
            reloadUser()
        } else if let projectPath {
            reloadProject(projectPath)
        }
    }

    // MARK: - History (spec/13 §3.3-3.4)

    public func history(actionID: String) -> [ActionVersion] {
        let directory = historyDirectory.appendingPathComponent(actionID)
        return Self.yamlFiles(in: directory)
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted(by: >) // yeniden eskiye
            .map(ActionVersion.init(timestamp:))
    }

    public func restore(actionID: String, version: String) throws {
        let backup = historyDirectory
            .appendingPathComponent(actionID)
            .appendingPathComponent("\(version).yaml")
        guard let content = try? String(contentsOf: backup, encoding: .utf8) else {
            throw LumiError.fileOperationFailed(path: version, detail: "backup not found")
        }
        let target = Self.findFile(withActionID: actionID, in: userDirectory)
            ?? userDirectory.appendingPathComponent("\(actionID).yaml")
        do {
            try content.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            throw LumiError.fileOperationFailed(path: actionID, detail: error.localizedDescription)
        }
        reloadUser()
    }

    // MARK: - AI destekli create/edit (spec/13 §3.8-3.9)

    public func createNew(repoPath: String?) async throws -> TerminalMeta {
        let provider = (await config.config()).aiProvider
        let synthetic = Self.syntheticPromptAction(
            id: "__create-action",
            label: "Create Action",
            prompt: ActionPrompts.createAction,
            provider: provider
        )
        return try await engine.execute(
            synthetic,
            repoPath: repoPath ?? userDirectory.path,
            provider: provider,
            builder: commandBuilder
        )
    }

    public func edit(actionID: String, projectPath: String?) async throws -> TerminalMeta {
        var file = Self.findFile(withActionID: actionID, in: userDirectory)
        if file == nil, let projectPath {
            file = Self.findFile(
                withActionID: actionID,
                in: URL(fileURLWithPath: projectPath).appendingPathComponent(".lumi/actions")
            )
        }
        guard let file, let content = try? String(contentsOf: file, encoding: .utf8) else {
            throw LumiError.underlying(domain: "action", message: "Action not found: \(actionID)")
        }
        let provider = (await config.config()).aiProvider
        let synthetic = Self.syntheticPromptAction(
            id: "__edit-action",
            label: "Edit: \(actionID)",
            prompt: ActionPrompts.editAction(yamlContent: content, filePath: file.path),
            provider: provider
        )
        return try await engine.execute(
            synthetic,
            repoPath: projectPath ?? userDirectory.path,
            provider: provider,
            builder: commandBuilder
        )
    }

    /// Claude: prompt appendSystemPrompt flag'iyle + `claude "."`;
    /// Codex: çağrı başına RASTGELE delimiter'lı heredoc (prompt injection guard'ı).
    static func syntheticPromptAction(
        id: String,
        label: String,
        prompt: String,
        provider: AgentProvider
    ) -> Action {
        switch provider {
        case .claude:
            return Action(
                id: id,
                label: label,
                claude: ClaudeAgentConfig(appendSystemPrompt: prompt),
                steps: [.write(content: "claude \".\"\r")]
            )
        case .codex:
            let delimiter = "__AI_ORCH_"
                + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
                + "__"
            let content = "codex exec - <<'\(delimiter)'\n\(prompt)\n\(delimiter)\r"
            return Action(id: id, label: label, steps: [.write(content: content)])
        }
    }

    // MARK: - Yükleme

    private func loadUserIfNeeded() {
        guard !userLoaded else { return }
        refreshFileStamps()
        reloadUser()
        ensureUserWatcher()
    }

    private func reloadUser() {
        userLoaded = true
        userActions = Self.yamlFiles(in: userDirectory).compactMap { url in
            guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let isDefault = PresetCodec.actionID(in: yaml).map(defaultIDs.contains) ?? false
            return PresetCodec.decodeAction(yaml, scope: .user, isDefault: isDefault)
        }
        broadcaster.send(())
    }

    private func loadProjectIfNeeded(_ projectPath: String) -> [Action] {
        if let cached = projectActions[projectPath] {
            return cached
        }
        let loaded = loadProject(projectPath)
        projectActions[projectPath] = loaded
        let directory = Self.projectDirectory(projectPath)
        if FileManager.default.fileExists(atPath: directory.path) {
            ensureWatcher(on: directory.path) { [weak self] in
                await self?.reloadProject(projectPath)
            }
        }
        return loaded
    }

    private func reloadProject(_ projectPath: String) {
        projectActions[projectPath] = loadProject(projectPath)
        broadcaster.send(())
    }

    private func loadProject(_ projectPath: String) -> [Action] {
        Self.yamlFiles(in: Self.projectDirectory(projectPath)).compactMap { url in
            guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return PresetCodec.decodeAction(yaml, scope: .project)
        }
    }

    private static func projectDirectory(_ projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath).appendingPathComponent(".lumi/actions")
    }

    // MARK: - Watcher + otomatik history (spec/13 §3.3)

    private func ensureUserWatcher() {
        ensureWatcher(on: userDirectory.path) { [weak self] in
            await self?.handleUserDirectoryChange()
        }
    }

    private func ensureWatcher(on path: String, _ handler: @escaping @Sendable () async -> Void) {
        guard watchers[path] == nil else { return }
        watchers[path] = DirectoryWatcher(path: path, queue: watchQueue, debounce: 0.3) {
            Task { await handler() }
        }
    }

    // Testler watcher debounce'unu beklemeden doğrudan sürebilsin diye internal
    func handleUserDirectoryChange() {
        let current = currentFileStamps()
        for (fileName, stamp) in current where fileStamps[fileName] != stamp {
            backup(fileName: fileName) // yeni veya değişmiş dosya → versiyonla
        }
        let deletedAny = fileStamps.keys.contains { current[$0] == nil }
        fileStamps = current
        if deletedAny {
            // Silinen default anında geri gelir (spec/13 §3.3)
            seedDefaults()
        } else {
            reloadUser()
        }
    }

    private func backup(fileName: String) {
        let source = userDirectory.appendingPathComponent(fileName)
        guard let content = try? String(contentsOf: source, encoding: .utf8) else { return }
        let actionID = PresetCodec.actionID(in: content)
            ?? (fileName as NSString).deletingPathExtension
        let directory = historyDirectory.appendingPathComponent(actionID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Saniye hassasiyetinde çakışmada sıra-koruyan `_N` soneki ('_' > '.')
        let base = Self.historyTimestamp(Date())
        var fileURL = directory.appendingPathComponent("\(base).yaml")
        var collisionIndex = 2
        while FileManager.default.fileExists(atPath: fileURL.path) {
            fileURL = directory.appendingPathComponent("\(base)_\(collisionIndex).yaml")
            collisionIndex += 1
        }
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)

        // Max 20: en eskiler silinir (best-effort)
        let backups = Self.yamlFiles(in: directory)
            .map(\.lastPathComponent)
            .sorted()
        if backups.count > Self.maxHistoryPerAction {
            for oldest in backups.prefix(backups.count - Self.maxHistoryPerAction) {
                try? FileManager.default.removeItem(
                    at: directory.appendingPathComponent(oldest)
                )
            }
        }
    }

    /// ISO timestamp; `:` → `-`, milisaniyesiz (spec/13 §3.3 format paritesi).
    static func historyTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter()
            .string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }

    private func refreshFileStamps() {
        fileStamps = currentFileStamps()
    }

    private func currentFileStamps() -> [String: Date] {
        var stamps: [String: Date] = [:]
        for url in Self.yamlFiles(in: userDirectory) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            stamps[url.lastPathComponent] = (attributes?[.modificationDate] as? Date) ?? .distantPast
        }
        return stamps
    }

    // MARK: - Dosya yardımcıları

    static func yamlFiles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func findFile(withActionID actionID: String, in directory: URL) -> URL? {
        yamlFiles(in: directory).first { url in
            guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return PresetCodec.actionID(in: yaml) == actionID
        }
    }
}
