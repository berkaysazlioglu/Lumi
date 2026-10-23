import Foundation

/// Orchestrator Codex'inin bir açılışı (karar 123): hangi talimatla, hangi
/// konuşmayı sürdürerek, Lumi'nin hangi MCP ucuna bağlanarak açılacağı.
public struct OrchestratorLaunchRequest: Sendable, Equatable {
    /// Codex'in `developer_instructions`'ı — her açılışta Lumi'nin canlı
    /// durumundan yeniden üretilir (`OrchestratorPrompt.make`).
    public let instructions: String
    /// Sürdürülecek Codex thread'i; nil = yeni konuşma.
    public let resumeThreadID: String?
    /// Lumi'nin MCP ucu — nil = araçsız (yalnız sohbet).
    public let control: OrchestratorControlEndpoint?
    /// Seçili Codex hesabının `CODEX_HOME`'u (karar 78); nil = sistem varsayılanı.
    public let codexHome: String?

    public init(
        instructions: String,
        resumeThreadID: String?,
        control: OrchestratorControlEndpoint?,
        codexHome: String?
    ) {
        self.instructions = instructions
        self.resumeThreadID = resumeThreadID
        self.control = control
        self.codexHome = codexHome
    }
}

/// Başlatıcının hazırladığı açılış: terminalin shell'ine yazılacak komut ve
/// PTY'ye eklenecek ortam (MCP token'ı argv'de değil burada taşınır).
public struct OrchestratorLaunchPlan: Sendable, Equatable {
    public let command: String
    public let environment: [String: String]

    public init(command: String, environment: [String: String]) {
        self.command = command
        self.environment = environment
    }
}

/// Orchestrator'ın Codex tarafı (karar 123): etkileşimli Codex TUI'sinin
/// açılış komutunu hazırlar ve çalışan konuşmaya mesaj kuyruklar.
public protocol OrchestratorLaunching: Sendable {
    func prepare(_ request: OrchestratorLaunchRequest) async throws -> OrchestratorLaunchPlan
    /// `codex queue`: mesaj çalışan konuşmaya, Codex boşalınca teslim edilir —
    /// kullanıcının composer'daki yarım taslağına dokunmaz.
    func queue(_ message: String, thread: String, codexHome: String?) async throws
}
