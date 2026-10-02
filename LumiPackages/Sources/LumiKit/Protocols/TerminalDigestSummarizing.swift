import Foundation

/// Bir ajanın son mesajının kısa özeti (karar 103 Faz 4).
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

/// Uzun ajan mesajlarını özetleyen yüz — `claude -p --model haiku`.
public protocol TerminalDigestSummarizing: Sendable {
    func summarize(agentMessage: String, terminalTitle: String) async throws -> TerminalDigest
}
