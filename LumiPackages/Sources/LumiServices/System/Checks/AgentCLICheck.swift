import Foundation
import LumiKit

/// Bir sağlayıcının CLI'ı PATH'te mi? Seçili sağlayıcıda bulunamaması FAIL ve
/// düzeltilebilir; seçili olmayanınki yalnızca WARN'dır (design/02 §8).
public struct AgentCLICheck: SystemCheck {
    public let provider: AgentProvider
    public var id: String { "\(provider.rawValue)-cli" }

    /// Kurulum sayfası — "Fix" aksiyonunun hedefi. Eşleme burada yaşar,
    /// AppDelegate'te bir `switch` olarak değil (refactor 3.6).
    public var setupURL: URL? {
        switch provider {
        case .claude: return URL(string: "https://code.claude.com/docs/en/setup")
        case .codex: return URL(string: "https://github.com/openai/codex")
        }
    }

    private let locator: any BinaryLocating
    private let timeout: TimeInterval

    public init(
        provider: AgentProvider,
        locator: any BinaryLocating = SystemBinaryLocator(),
        timeout: TimeInterval = SystemService.commandTimeout
    ) {
        self.provider = provider
        self.locator = locator
        self.timeout = timeout
    }

    public func run(context: SystemCheckContext) async -> SystemCheckResult {
        let binary = provider.rawValue
        let label = "\(binary) CLI"
        if let found = await locator.locate(binary, timeout: timeout) {
            return SystemCheckResult(id: id, label: label, status: .pass, message: found)
        }
        if provider == context.selectedProvider {
            return SystemCheckResult(
                id: id, label: label, status: .fail,
                message: "\(binary) not found in PATH", isFixable: true,
                fixURL: setupURL
            )
        }
        return SystemCheckResult(
            id: id, label: label, status: .warn,
            message: "\(binary) not found (not selected provider)"
        )
    }
}
