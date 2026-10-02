import Foundation
import LumiWire

/// Orchestrator oturumunun açılışı (karar 103): hangi Claude konuşmasının
/// sürdürüleceği. Kimlik Lumi'de üretilir ve `ui-state`'e yazılır; ilk
/// açılışta `--session-id`, sonrakilerde `--resume` ile aynı konuşma açılır.
public struct OrchestratorLaunch: Sendable, Equatable {
    public let sessionID: String
    /// `true` = konuşma daha önce başladı, transkriptten geçmiş okunur.
    public let resume: Bool
    /// Lumi'nin MCP ucu (Faz 2) — nil = araçsız sohbet.
    public let control: OrchestratorControlEndpoint?

    public init(sessionID: String, resume: Bool, control: OrchestratorControlEndpoint? = nil) {
        self.sessionID = sessionID
        self.resume = resume
        self.control = control
    }
}

/// Bir orchestrator sürecinin yaşamı: geçmiş (resume'da transkriptten) +
/// canlı journal akışı. Akış süreç çıkınca biter.
public struct OrchestratorRun: Sendable {
    public let history: [ChatMessage]
    public let updates: AsyncStream<ChatJournalState>

    public init(history: [ChatMessage], updates: AsyncStream<ChatJournalState>) {
        self.history = history
        self.updates = updates
    }
}

/// Lumi'deki tüm ajan terminallerini yöneten orchestrator Claude'u (karar
/// 103). PTY'siz bir `claude -p` stream-json child'ıdır; kendi system
/// prompt'u vardır, kullanıcı/proje ayarlarını ve `CLAUDE.md`'leri yüklemez.
public protocol OrchestratorServicing: Sendable {
    /// Süreci başlatır. Zaten çalışan bir süreç varsa önce durdurulur.
    func start(_ launch: OrchestratorLaunch) async throws -> OrchestratorRun
    /// Kullanıcı mesajını stdin'e yazar (süreç yoksa yutulur — çağıran
    /// önce `start` eder).
    func send(_ text: String) async
    /// Süreci sonlandırır; konuşma transkriptte kalır, `resume` ile döner.
    func stop() async
}
