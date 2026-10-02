import Foundation

/// POSIX tek-tırnak quoting: ' → '\'' . Bir argümanı shell komut satırına
/// güvenle gömmek için (telefondan ve orchestrator'dan açılan
/// `claude '<prompt>'` terminalleri — karar 89/103).
public func shellQuoted(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
