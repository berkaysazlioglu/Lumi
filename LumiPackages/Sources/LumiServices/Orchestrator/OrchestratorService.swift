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
            extraArguments: Self.arguments(),
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

    static func arguments() -> [String] {
        [
            "--replay-user-messages",
            "--system-prompt", OrchestratorPrompt.systemPrompt,
            "--system-prompt-snapshot", "off",
            "--setting-sources", "",
            "--strict-mcp-config",
            "--tools", "",
            "--model", model,
        ]
    }
}

/// Çözülmüş binary yolunu oturuma aktarır (ikinci arama yapılmaz).
private struct FixedLocator: BinaryLocating {
    let path: String
    func locate(_ name: String, timeout: TimeInterval) async -> String? { path }
}
