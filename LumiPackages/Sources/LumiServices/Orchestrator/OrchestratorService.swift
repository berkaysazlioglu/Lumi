import Foundation
import LumiKit

/// Orchestrator Claude'unun süreç yöneticisi (karar 103).
///
/// Mevcut stream-json motorunu (`StreamJsonAgentSession`) kendi bayraklarıyla
/// çalıştırır:
/// - `--system-prompt` + `--system-prompt-snapshot off`: Lumi'nin prompt'u,
///   her açılışta güncel metin.
/// - `--setting-sources ""` + `--strict-mcp-config`: kullanıcı/proje ayarı,
///   hook'u ve MCP sunucusu yüklenmez — Lumi'nin kendi hook'ları orchestrator'ı
///   bir ajan terminali sanmaz (karar 45/94 döngü riski).
/// - `--tools ""`: yerleşik araç yok; kontrol yüzeyi ayrı gelir.
/// - `--replay-user-messages`: kullanıcı mesajı journal'a stdout'tan düşer —
///   sıra modelin gördüğü sırayla aynı kalır.
///
/// CWD `~/.lumi/orchestrator`: hiçbir projenin `CLAUDE.md`'si okunmaz ve
/// transkriptler projelerin Agent History'sine karışmaz.
public actor OrchestratorService: OrchestratorServicing {
    public static let binaryName = "claude"
    public static let model = "sonnet"

    private let workingDirectory: URL
    private let environment: [String: String]
    private let spawner: any StreamingProcessSpawning
    private let locator: any BinaryLocating
    private let transcripts: TranscriptChatSource
    private var session: StreamJsonAgentSession?

    public init(
        workingDirectory: URL,
        environment: [String: String],
        spawner: any StreamingProcessSpawning = LiveStreamingProcess(),
        locator: any BinaryLocating = SystemBinaryLocator(),
        transcripts: TranscriptChatSource = TranscriptChatSource()
    ) {
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.spawner = spawner
        self.locator = locator
        self.transcripts = transcripts
    }

    public func start(_ launch: OrchestratorLaunch) async throws -> OrchestratorRun {
        await stop()
        guard let binary = await locator.locate(Self.binaryName) else {
            throw LumiError.cliNotFound(binary: Self.binaryName)
        }
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let history = launch.resume
            ? transcripts.messages(sessionID: launch.sessionID, repoPath: workingDirectory.path)
            : []
        let session = StreamJsonAgentSession(
            sessionID: launch.sessionID,
            repoPath: workingDirectory.path,
            environment: environment,
            // Konuşmanın transkripti yoksa (silinmiş / hiç mesaj gitmemiş)
            // `--resume` hata verir; yeni konuşma aynı kimlikle açılır.
            resume: launch.resume && !history.isEmpty,
            extraArguments: try arguments(control: launch.control),
            spawner: spawner,
            binaryLocator: FixedLocator(path: binary)
        )
        self.session = session
        // Abonelik spawn'dan ÖNCE: ilk satırlar kaçmaz.
        let updates = await session.snapshots()
        await session.start()
        return OrchestratorRun(history: history, updates: updates)
    }

    public func send(_ text: String) async {
        await session?.send(text)
    }

    public func stop() async {
        await session?.stop()
        session = nil
    }

    static func arguments(mcpConfigPath: String?) -> [String] {
        var args = [
            "--replay-user-messages",
            "--system-prompt", OrchestratorPrompt.systemPrompt,
            "--system-prompt-snapshot", "off",
            "--setting-sources", "",
            "--strict-mcp-config",
            "--tools", "",
            "--model", model,
        ]
        if let mcpConfigPath {
            // Yalnız Lumi sunucusunun araçları izinli; izin onayı Lumi'nin
            // kendi araç yürütücüsündedir (yazma araçları popup'ta onaylanır).
            args += ["--mcp-config", mcpConfigPath, "--allowedTools", OrchestratorTools.allowRule]
        }
        return args
    }

    /// MCP bağlantısı token taşıdığı için argv'ye değil 0600 bir dosyaya yazılır
    /// (`ps` çıktısında görünmesin).
    private func arguments(control: OrchestratorControlEndpoint?) throws -> [String] {
        guard let control else { return Self.arguments(mcpConfigPath: nil) }
        let file = workingDirectory.appendingPathComponent(Self.mcpConfigFileName)
        try Self.mcpConfig(control).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return Self.arguments(mcpConfigPath: file.path)
    }

    static let mcpConfigFileName = "mcp.json"

    static func mcpConfig(_ control: OrchestratorControlEndpoint) throws -> Data {
        let config: [String: Any] = ["mcpServers": [
            OrchestratorTools.serverName: [
                "type": "http",
                "url": control.url,
                "headers": ["Authorization": "Bearer \(control.token)"],
            ],
        ]]
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }
}

/// Çözülmüş binary yolunu oturuma aktarır (ikinci arama yapılmaz).
private struct FixedLocator: BinaryLocating {
    let path: String
    func locate(_ name: String, timeout: TimeInterval) async -> String? { path }
}
