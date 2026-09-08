import Foundation

/// İçe aktarma sonucu: dosyanın nereye yazıldığı ve (çakışmada) yeni kimlik.
public struct AgentSessionImportResult: Sendable, Equatable {
    public let provider: AgentProvider
    public let sessionID: String
    public let logPath: String
    public let subagentCount: Int
    /// Aynı kimlikte oturum zaten vardı; yeni bir kimlik üretildi.
    public let didRenameSession: Bool

    public init(provider: AgentProvider, sessionID: String, logPath: String,
                subagentCount: Int, didRenameSession: Bool) {
        self.provider = provider
        self.sessionID = sessionID
        self.logPath = logPath
        self.subagentCount = subagentCount
        self.didRenameSession = didRenameSession
    }
}

/// Agent History oturumlarını tek dosyalık paket olarak dışa/içe aktarır
/// (karar 52). Dışa aktarma kişisel kayıtları ayıklar; içe aktarma yolları
/// hedef projeye göre yeniden yazar ve sağlayıcının kendi dizinine yerleştirir.
public protocol AgentSessionTransferring: Sendable {
    func exportSession(_ entry: AgentHistoryEntry, to destination: URL) async throws
    func importSession(from source: URL, projectPath: String) async throws -> AgentSessionImportResult
}
