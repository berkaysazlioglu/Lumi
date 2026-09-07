import Foundation

/// App-geneli tek tip hata sözleşmesi (karar 5, design/02 §9).
/// Her servis iç hatasını kendi sınırında bu tipe map'ler; kullanıcıyı etkileyen
/// her hata ToastStore üzerinden görünür şekilde sunulur.
public enum LumiError: Error, LocalizedError, Sendable, Equatable {
    case spawnFailed(reason: String)
    case terminalNotFound(TerminalID)
    case gitFailed(operation: String, detail: String)
    /// Plastic SCM `cm` yazma operasyonu (checkin/undo) başarısız (karar 46).
    case plasticFailed(operation: String, detail: String)
    /// Commit mesajı üretimi (`claude -p`) başarısız ya da boş yanıt (karar 47).
    case commitMessageGenerationFailed(detail: String)
    case pathOutsideRepo(path: String)
    case fileOperationFailed(path: String, detail: String)
    case configIOFailed(file: String, detail: String)
    case externalURLBlocked(URL)
    case systemCheckFailed(check: String, detail: String)
    case cliNotFound(binary: String)
    case usageUnavailable(detail: String)
    case sessionStartFailed(detail: String)
    case underlying(domain: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .spawnFailed(let reason):
            return "Failed to start terminal: \(reason)"
        case .terminalNotFound(let id):
            return "Terminal not found: \(id)"
        case .gitFailed(let operation, let detail):
            return "Git \(operation) failed: \(detail)"
        case .plasticFailed(let operation, let detail):
            return "Plastic SCM \(operation) failed: \(detail)"
        case .commitMessageGenerationFailed(let detail):
            return "Could not generate commit message: \(detail)"
        case .pathOutsideRepo(let path):
            return "Path is outside the repository: \(path)"
        case .fileOperationFailed(let path, let detail):
            return "File operation failed for \(path): \(detail)"
        case .configIOFailed(let file, let detail):
            return "Could not read or write \(file): \(detail)"
        case .externalURLBlocked(let url):
            return "Blocked external URL (only http/https allowed): \(url.absoluteString)"
        case .systemCheckFailed(let check, let detail):
            return "System check \(check) failed: \(detail)"
        case .cliNotFound(let binary):
            return "\(binary) CLI not found in PATH."
        case .usageUnavailable(let detail):
            return "Could not read usage: \(detail)"
        case .sessionStartFailed(let detail):
            return "Could not start session: \(detail)"
        case .underlying(let domain, let message):
            return "\(domain): \(message)"
        }
    }
}
