import Foundation

/// PTY smoke testinin dikiş yeri: SystemService LumiTerminal'i import edemez
/// (bağımlılık yönü, design/00 §2) — implementasyon LumiTerminal'de yaşar,
/// composition root enjekte eder.
public protocol TerminalSmokeTesting: Sendable {
    func runSmokeTest() async throws
}

/// Tek bir sağlık kontrolünün sınırı (refactor 3.9). `SystemService` bunları
/// bir dizi olarak alır ve sırayla koşturur; yeni kontrol eklemek yeni bir
/// dosya + composition root'ta bir satırdır (OCP).
public protocol SystemCheck: Sendable {
    /// Ürettiği `SystemCheckResult.id` ile aynı — sonuçların kimliği tek yerden.
    var id: String { get }
    func run(context: SystemCheckContext) async -> SystemCheckResult
}

/// Kontrollerin koşum bağlamı. Bugün yalnız seçili sağlayıcıyı taşır
/// (claude/codex CLI kontrolünün fail/warn ayrımı buna bağlıdır).
public struct SystemCheckContext: Sendable, Equatable {
    public let selectedProvider: AgentProvider

    public init(selectedProvider: AgentProvider) {
        self.selectedProvider = selectedProvider
    }
}

/// Sistem sağlığı + platform yardımcıları sınırı (design/02 §8).
public protocol SystemServicing: Sendable {
    /// Check'ler async koşar (senkron SystemChecker taşınmaz — karar 11).
    func runChecks(selectedProvider: AgentProvider) async -> [SystemCheckResult]

    /// GUI app'in minimal PATH problemi ): `$SHELL -ilc`
    /// PATH'i + bilinen dizinler. Startup'ta bir kez, her spawn'dan ÖNCE.
    func fixProcessPath() async

    /// Yalnız http/https (whitelist paritesi); ihlal görünür hatadır (karar 5).
    func openExternal(_ url: URL) throws

    func trash(path: String) async throws
    func revealInFinder(path: String)
    @MainActor func chooseFolder() async -> String?
}
