import Foundation
import LumiKit

/// Persona servisi (spec/13 §2). Seed asimetrisinin persona tarafı:
/// default'lar HER startup'ta üzerine yazılır — rol şablonları kanoniktir,
/// kullanıcı düzenlemeleri restart'ta kaybolur (bilinçli davranış).
public actor PersonaService: PersonaServicing {
    private let userDirectory: URL
    private let seedDirectory: URL?
    private let terminal: any TerminalServicing
    private let config: any ConfigServicing
    private let commandBuilder: AgentCommandBuilder
    private let broadcaster = EventBroadcaster<Void>()
    private let watchQueue = DispatchQueue(label: "lumi.personas.watch", qos: .utility)

    private var userPersonas: [Persona] = []
    private var projectPersonas: [String: [Persona]] = [:]
    private var watchers: [String: DirectoryWatcher] = [:]
    private var userLoaded = false

    public init(
        paths: LumiPaths,
        seedDirectory: URL?,
        terminal: any TerminalServicing,
        config: any ConfigServicing
    ) {
        self.userDirectory = paths.personasDir
        self.seedDirectory = seedDirectory
        self.terminal = terminal
        self.config = config
        self.commandBuilder = AgentCommandBuilder(tempDirectory: paths.tempDir)
    }

    // MARK: - Seed (her startup'ta EZİLİR — spec/13 §2.2)

    public func seedDefaults() {
        try? FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        if let seedDirectory {
            for seed in yamlFiles(in: seedDirectory) {
                let target = userDirectory.appendingPathComponent(seed.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: seed, to: target)
            }
        }
        reloadUser()
        ensureWatcher(on: userDirectory.path) { [weak self] in
            await self?.reloadUser()
        }
    }

    // MARK: - Listeleme / scope merge (spec/13 §2.4)

    public func personas(projectPath: String?) -> [Persona] {
        loadUserIfNeeded()
        var result = userPersonas
        if let projectPath {
            let project = loadProjectIfNeeded(projectPath)
            let projectIDs = Set(project.map(\.id))
            // Project persona aynı id'li user persona'yı GİZLER
            result = result.filter { !projectIDs.contains($0.id) } + project
        }
        return result
    }

    public func events() -> AsyncStream<Void> {
        broadcaster.stream()
    }

    // MARK: - Spawn (spec/13 §2.5)

    public func spawn(personaID: String, repoPath: String) async throws -> TerminalMeta {
        guard let persona = personas(projectPath: repoPath).first(where: { $0.id == personaID }) else {
            throw LumiError.underlying(domain: "persona", message: "Persona not found: \(personaID)")
        }
        let provider: AgentProvider
        if let explicit = persona.provider {
            provider = explicit
        } else {
            provider = (await config.config()).aiProvider
        }
        // Base komut: claude için `claude ""`, codex için `codex`
        let base = provider == .claude ? "claude \"\"\r" : "codex\r"
        let command = try commandBuilder.build(
            content: base,
            provider: provider,
            claude: persona.claude,
            codex: persona.codex
        )
        let meta = try await terminal.spawn(repoPath: repoPath, task: persona.label, command: nil)
        try await terminal.write(id: meta.id, text: command)
        return meta
    }

    // MARK: - Yükleme

    private func loadUserIfNeeded() {
        guard !userLoaded else { return }
        reloadUser()
    }

    private func reloadUser() {
        userLoaded = true
        userPersonas = load(directory: userDirectory, scope: .user)
        broadcaster.send(())
    }

    private func loadProjectIfNeeded(_ projectPath: String) -> [Persona] {
        if let cached = projectPersonas[projectPath] {
            return cached
        }
        let directory = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".lumi/personas")
        let loaded = load(directory: directory, scope: .project)
        projectPersonas[projectPath] = loaded
        // Dizin yoksa watcher kurulmaz (spec/13 §2.3)
        if FileManager.default.fileExists(atPath: directory.path) {
            ensureWatcher(on: directory.path) { [weak self] in
                await self?.reloadProject(projectPath, directory: directory)
            }
        }
        return loaded
    }

    private func reloadProject(_ projectPath: String, directory: URL) {
        projectPersonas[projectPath] = load(directory: directory, scope: .project)
        broadcaster.send(())
    }

    private func load(directory: URL, scope: PresetScope) -> [Persona] {
        yamlFiles(in: directory).compactMap { url in
            guard let yaml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return PresetCodec.decodePersona(yaml, scope: scope)
        }
    }

    private func yamlFiles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func ensureWatcher(on path: String, _ reload: @escaping @Sendable () async -> Void) {
        guard watchers[path] == nil else { return }
        watchers[path] = DirectoryWatcher(path: path, queue: watchQueue, debounce: 0.3) {
            Task { await reload() }
        }
    }
}
