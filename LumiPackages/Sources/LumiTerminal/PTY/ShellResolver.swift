import Foundation

/// Login shell seçimi (spec/10 §1): macOS zinciri zsh → bash → sh,
/// process ömrü boyunca cache'lenir. Bilinen mutlak path'ler kullanılır —
/// GUI app'in minimal PATH'inden etkilenmez.
enum ShellResolver {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    static let candidates = ["/bin/zsh", "/bin/bash", "/bin/sh"]

    static func defaultShell() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let found = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/bin/sh"
        cached = found
        return found
    }
}
