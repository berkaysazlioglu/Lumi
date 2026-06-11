import Foundation

public struct SystemCheckResult: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable {
        case pass
        case warn
        case fail
    }

    public let id: String
    public let label: String
    public let status: Status
    public let message: String
    public let isFixable: Bool

    public init(id: String, label: String, status: Status, message: String, isFixable: Bool = false) {
        self.id = id
        self.label = label
        self.status = status
        self.message = message
        self.isFixable = isFixable
    }
}

/// PTY smoke testinin dikiş yeri: SystemService LumiTerminal'i import edemez
/// (bağımlılık yönü, design/00 §2) — implementasyon LumiTerminal'de yaşar,
/// composition root enjekte eder.
public protocol TerminalSmokeTesting: Sendable {
    func runSmokeTest() async throws
}

/// Sistem sağlığı + platform yardımcıları sınırı (design/02 §8).
public protocol SystemServicing: Sendable {
    /// Check'ler async koşar (senkron SystemChecker taşınmaz — karar 11).
    func runChecks(selectedProvider: AgentProvider) async -> [SystemCheckResult]

    /// GUI app'in minimal PATH problemi (spec/10 §Electron-3): `$SHELL -ilc`
    /// PATH'i + bilinen dizinler. Startup'ta bir kez, her spawn'dan ÖNCE.
    func fixProcessPath() async

    /// Yalnız http/https (whitelist paritesi); ihlal görünür hatadır (karar 5).
    func openExternal(_ url: URL) throws

    func trash(path: String) async throws
    func revealInFinder(path: String)
    @MainActor func chooseFolder() async -> String?
}
