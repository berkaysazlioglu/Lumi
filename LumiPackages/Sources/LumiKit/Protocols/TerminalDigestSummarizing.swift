import Foundation

/// Bir ajanın son mesajının kısa özeti (karar 114 Faz 4).
public struct TerminalDigest: Sendable, Equatable {
    /// 1–3 kısa satır.
    public let summary: String
    /// Ajan kullanıcıdan cevap/karar/onay bekliyor mu?
    public let needsUser: Bool

    public init(summary: String, needsUser: Bool) {
        self.summary = summary
        self.needsUser = needsUser
    }
}

/// Ajan terminallerini özetleyen yüz — `claude -p --model haiku`.
public protocol TerminalDigestSummarizing: Sendable {
    /// Bir turn'ün son (uzun) mesajı → 1–3 satır.
    func summarize(agentMessage: String, terminalTitle: String) async throws -> TerminalDigest
    /// Orchestrator bir terminali SONRADAN izlemeye aldığında: oturumun o ana
    /// kadarki konuşması → hedef, yapılanlar, son durum.
    func summarizeSession(transcript: String, terminalTitle: String) async throws -> TerminalDigest
}
